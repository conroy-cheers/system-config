import argparse
import email.policy
import hashlib
import ipaddress
import mimetypes
import re
import smtplib
import socket
import ssl
import time
import unicodedata
from collections import deque
from dataclasses import dataclass
from email.headerregistry import Address
from email.message import EmailMessage
from email.utils import formatdate, make_msgid
from pathlib import Path
from threading import Lock
from urllib.parse import urljoin, urlsplit

import httpx
from fastmcp.client.transports import StdioTransport
from fastmcp.server import create_proxy
from fastmcp.server.auth import RemoteAuthProvider
from fastmcp.server.auth.providers.jwt import JWTVerifier
from fastmcp.server.providers.proxy import ProxyClient
from fastmcp.utilities.authorization import require_scopes
from mcp.types import ToolAnnotations
from pydantic import AnyHttpUrl, BaseModel, ConfigDict, Field


MIME_TYPE_RE = re.compile(
    r"^[A-Za-z0-9!#$&^_.+\-]+/[A-Za-z0-9!#$&^_.+\-]+$"
)
REDIRECT_STATUS_CODES = frozenset({301, 302, 303, 307, 308})
MAX_DOWNLOAD_URL_CHARS = 16384
MAX_ATTACHMENT_FILENAME_BYTES = 180
DOWNLOAD_CHUNK_BYTES = 65536


class ChatGPTFile(BaseModel):
    """A file value supplied by ChatGPT through openai/fileParams."""

    model_config = ConfigDict(extra="forbid")

    download_url: str = Field(min_length=1, max_length=MAX_DOWNLOAD_URL_CHARS)
    file_id: str = Field(min_length=1, max_length=512)
    mime_type: str = Field(default="", max_length=255)
    file_name: str = Field(default="", max_length=1024)


@dataclass(frozen=True)
class AttachmentPolicy:
    allowed_host_suffixes: tuple[str, ...]
    max_count: int
    max_file_bytes: int
    max_total_bytes: int
    max_encoded_message_bytes: int
    max_redirects: int
    connect_timeout_seconds: float
    read_timeout_seconds: float
    overall_timeout_seconds: float


@dataclass(frozen=True)
class DownloadedAttachment:
    file_name: str
    mime_type: str
    data: bytes
    sha256: str

    def result(self):
        return {
            "file_name": self.file_name,
            "mime_type": self.mime_type,
            "bytes": len(self.data),
            "sha256": self.sha256,
        }


class AttachmentError(ValueError):
    pass


class SMTPDeliveryError(RuntimeError):
    def __init__(self, message, *, uncertain=False):
        super().__init__(message)
        self.uncertain = uncertain


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Expose a stdio mail MCP server over authenticated Streamable HTTP."
    )
    parser.add_argument("--backend-command", required=True)
    parser.add_argument("--listen-address", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8781)
    parser.add_argument("--path", default="/mcp")
    parser.add_argument("--public-url", required=True)
    parser.add_argument("--issuer", required=True)
    parser.add_argument("--jwks-uri", required=True)
    parser.add_argument("--audience", required=True)
    parser.add_argument("--required-scope", action="append", required=True)
    parser.add_argument("--supported-scope", action="append", default=[])

    smtp = parser.add_argument_group("SMTP sending")
    smtp.add_argument("--smtp-host")
    smtp.add_argument("--smtp-port", type=int, default=587)
    smtp.add_argument("--smtp-username")
    smtp.add_argument("--smtp-password-file")
    smtp.add_argument("--smtp-sender-address")
    smtp.add_argument("--smtp-sender-name", default="")
    smtp.add_argument("--smtp-send-scope", default="mail.send")
    smtp.add_argument("--smtp-max-recipients", type=int, default=20)
    smtp.add_argument("--smtp-max-subject-chars", type=int, default=998)
    smtp.add_argument("--smtp-max-body-chars", type=int, default=200000)
    smtp.add_argument("--smtp-max-messages-per-hour", type=int, default=20)
    smtp.add_argument("--smtp-attachments-enabled", action="store_true")
    smtp.add_argument("--smtp-attachment-allowed-host", action="append", default=[])
    smtp.add_argument("--smtp-max-attachments", type=int, default=5)
    smtp.add_argument("--smtp-max-attachment-bytes", type=int, default=8 * 1024 * 1024)
    smtp.add_argument(
        "--smtp-max-total-attachment-bytes", type=int, default=10 * 1024 * 1024
    )
    smtp.add_argument(
        "--smtp-max-encoded-message-bytes", type=int, default=15 * 1024 * 1024
    )
    smtp.add_argument("--smtp-attachment-max-redirects", type=int, default=3)
    smtp.add_argument(
        "--smtp-attachment-connect-timeout-seconds", type=float, default=5
    )
    smtp.add_argument(
        "--smtp-attachment-read-timeout-seconds", type=float, default=20
    )
    smtp.add_argument(
        "--smtp-attachment-overall-timeout-seconds", type=float, default=45
    )

    args = parser.parse_args(argv)
    smtp_required = (
        args.smtp_host,
        args.smtp_username,
        args.smtp_password_file,
        args.smtp_sender_address,
    )
    if any(smtp_required) and not all(smtp_required):
        parser.error(
            "SMTP sending requires --smtp-host, --smtp-username, "
            "--smtp-password-file, and --smtp-sender-address"
        )
    if args.smtp_max_recipients < 1:
        parser.error("--smtp-max-recipients must be positive")
    if args.smtp_max_messages_per_hour < 1:
        parser.error("--smtp-max-messages-per-hour must be positive")
    if args.smtp_attachments_enabled:
        positive_attachment_limits = (
            args.smtp_max_attachments,
            args.smtp_max_attachment_bytes,
            args.smtp_max_total_attachment_bytes,
            args.smtp_max_encoded_message_bytes,
            args.smtp_attachment_connect_timeout_seconds,
            args.smtp_attachment_read_timeout_seconds,
            args.smtp_attachment_overall_timeout_seconds,
        )
        if not all(value > 0 for value in positive_attachment_limits):
            parser.error("SMTP attachment size, count, and timeout limits must be positive")
        if args.smtp_attachment_max_redirects < 0:
            parser.error("--smtp-attachment-max-redirects must not be negative")
        if not args.smtp_attachment_allowed_host:
            parser.error(
                "SMTP attachments require at least one --smtp-attachment-allowed-host"
            )
        if args.smtp_max_attachment_bytes > args.smtp_max_total_attachment_bytes:
            parser.error(
                "--smtp-max-attachment-bytes must not exceed the total attachment limit"
            )
        if args.smtp_max_encoded_message_bytes <= (
            args.smtp_max_total_attachment_bytes
        ):
            parser.error(
                "--smtp-max-encoded-message-bytes must exceed the raw attachment limit"
            )
    return args


def normalize_address(value):
    value = value.strip()
    if not value or "\r" in value or "\n" in value:
        raise ValueError("Email addresses must be non-empty addr-spec values.")
    try:
        address = Address(addr_spec=value)
    except ValueError as error:
        raise ValueError(f"Invalid email address: {value}") from error
    if not address.username or not address.domain:
        raise ValueError(f"Invalid email address: {value}")
    return str(address)


def normalize_recipients(to, cc, bcc, maximum):
    normalized = []
    seen = set()
    for value in [*to, *(cc or []), *(bcc or [])]:
        address = normalize_address(value)
        key = address.casefold()
        if key not in seen:
            normalized.append(address)
            seen.add(key)
    if not normalized:
        raise ValueError("At least one recipient is required.")
    if len(normalized) > maximum:
        raise ValueError(f"At most {maximum} unique recipients are allowed.")
    return normalized


def validate_header(value, name, maximum):
    if "\r" in value or "\n" in value:
        raise ValueError(f"{name} must not contain newline characters.")
    if len(value) > maximum:
        raise ValueError(f"{name} must be at most {maximum} characters.")
    return value


def normalize_allowed_host(value):
    value = value.strip().lower()
    if value.startswith("."):
        value = value[1:]
    if not value or value.endswith(".") or "." not in value:
        raise ValueError("Attachment download hosts must be DNS suffixes.")
    try:
        return value.encode("idna").decode("ascii")
    except UnicodeError as error:
        raise ValueError("Attachment download hosts must be valid DNS names.") from error


def host_matches_suffix(host, suffix):
    return host == suffix or host.endswith(f".{suffix}")


def resolve_host_addresses(host):
    try:
        results = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    except OSError as error:
        raise AttachmentError("An attachment download host could not be resolved.") from error
    addresses = {result[4][0] for result in results}
    if not addresses:
        raise AttachmentError("An attachment download host returned no addresses.")
    return addresses


def validate_download_url(url, allowed_host_suffixes, resolver=resolve_host_addresses):
    if len(url) > MAX_DOWNLOAD_URL_CHARS:
        raise AttachmentError("An attachment download URL is too long.")
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError as error:
        raise AttachmentError("An attachment download URL is invalid.") from error
    if parsed.scheme != "https":
        raise AttachmentError("Attachment downloads require HTTPS.")
    if not parsed.hostname or parsed.username is not None or parsed.password is not None:
        raise AttachmentError("An attachment download URL has an invalid authority.")
    if parsed.fragment:
        raise AttachmentError("Attachment download URLs must not contain fragments.")
    if port not in (None, 443):
        raise AttachmentError("Attachment downloads must use HTTPS port 443.")
    if parsed.hostname.endswith("."):
        raise AttachmentError("Attachment download hosts must not end with a dot.")
    try:
        host = parsed.hostname.encode("idna").decode("ascii").lower()
    except UnicodeError as error:
        raise AttachmentError("An attachment download host is invalid.") from error
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        raise AttachmentError("Attachment download URLs must use an allowed DNS host.")
    if not any(host_matches_suffix(host, suffix) for suffix in allowed_host_suffixes):
        raise AttachmentError("An attachment download host is not allowed.")
    addresses = resolver(host)
    for address in addresses:
        try:
            parsed_address = ipaddress.ip_address(address)
        except ValueError as error:
            raise AttachmentError(
                "An attachment download host returned an invalid address."
            ) from error
        if not parsed_address.is_global:
            raise AttachmentError(
                "An attachment download host resolved to a non-public address."
            )
    return url


def truncate_utf8(value, maximum):
    while len(value.encode("utf-8")) > maximum:
        value = value[:-1]
    return value


def normalize_filename(value, index):
    value = unicodedata.normalize("NFC", value or "")
    value = value.replace("\\", "/").rsplit("/", 1)[-1]
    value = "".join(
        character
        for character in value
        if unicodedata.category(character) not in {"Cc", "Cf"}
    )
    value = value.strip(" .")
    if not value:
        return f"attachment-{index}"
    suffix = Path(value).suffix
    if suffix and len(suffix.encode("utf-8")) <= 32:
        stem = value[: -len(suffix)]
        stem = truncate_utf8(
            stem,
            MAX_ATTACHMENT_FILENAME_BYTES - len(suffix.encode("utf-8")),
        )
        value = f"{stem}{suffix}"
    else:
        value = truncate_utf8(value, MAX_ATTACHMENT_FILENAME_BYTES)
    return value or f"attachment-{index}"


def normalize_mime_type(value, file_name):
    value = (value or "").strip().lower()
    if MIME_TYPE_RE.fullmatch(value) and not value.startswith("multipart/"):
        return value
    guessed, _ = mimetypes.guess_type(file_name)
    if guessed and MIME_TYPE_RE.fullmatch(guessed) and not guessed.startswith(
        "multipart/"
    ):
        return guessed
    return "application/octet-stream"


def content_length(response):
    value = response.headers.get("content-length")
    if value is None:
        return None
    try:
        result = int(value)
    except ValueError:
        return None
    return result if result >= 0 else None


def download_one_attachment(
    source,
    *,
    index,
    policy,
    client,
    resolver,
    remaining_bytes,
    deadline,
):
    file_name = normalize_filename(source.file_name, index)
    mime_type = normalize_mime_type(source.mime_type, file_name)
    current_url = source.download_url
    redirects = 0

    while True:
        if time.monotonic() >= deadline:
            raise AttachmentError("The attachment download deadline was exceeded.")
        validate_download_url(current_url, policy.allowed_host_suffixes, resolver)
        try:
            with client.stream("GET", current_url, headers={"Accept": "*/*"}) as response:
                if response.status_code in REDIRECT_STATUS_CODES:
                    location = response.headers.get("location")
                    if not location or redirects >= policy.max_redirects:
                        raise AttachmentError("An attachment had too many redirects.")
                    current_url = urljoin(current_url, location)
                    redirects += 1
                    continue
                response.raise_for_status()
                declared_length = content_length(response)
                if declared_length is not None and declared_length > min(
                    policy.max_file_bytes, remaining_bytes
                ):
                    raise AttachmentError("An attachment exceeds the configured size limit.")
                data = bytearray()
                digest = hashlib.sha256()
                for chunk in response.iter_bytes(chunk_size=DOWNLOAD_CHUNK_BYTES):
                    if time.monotonic() >= deadline:
                        raise AttachmentError(
                            "The attachment download deadline was exceeded."
                        )
                    if not chunk:
                        continue
                    if len(data) + len(chunk) > policy.max_file_bytes:
                        raise AttachmentError(
                            "An attachment exceeds the per-file size limit."
                        )
                    if len(data) + len(chunk) > remaining_bytes:
                        raise AttachmentError(
                            "The attachments exceed the total size limit."
                        )
                    data.extend(chunk)
                    digest.update(chunk)
        except AttachmentError:
            raise
        except httpx.HTTPError:
            raise AttachmentError("An attachment could not be downloaded.") from None
        return DownloadedAttachment(
            file_name=file_name,
            mime_type=mime_type,
            data=bytes(data),
            sha256=digest.hexdigest(),
        )


def download_attachments(sources, policy, *, client=None, resolver=resolve_host_addresses):
    if len(sources) > policy.max_count:
        raise AttachmentError(f"At most {policy.max_count} attachments are allowed.")
    seen_file_ids = set()
    for source in sources:
        if source.file_id in seen_file_ids:
            raise AttachmentError("The same ChatGPT file was attached more than once.")
        seen_file_ids.add(source.file_id)
    if not sources:
        return []

    owns_client = client is None
    if client is None:
        timeout = httpx.Timeout(
            connect=policy.connect_timeout_seconds,
            read=policy.read_timeout_seconds,
            write=policy.read_timeout_seconds,
            pool=policy.connect_timeout_seconds,
        )
        client = httpx.Client(
            follow_redirects=False,
            timeout=timeout,
            trust_env=False,
            headers={"User-Agent": "icloud-mail-mcp-gateway/1"},
        )
    deadline = time.monotonic() + policy.overall_timeout_seconds
    downloaded = []
    total_bytes = 0
    try:
        for index, source in enumerate(sources, start=1):
            attachment = download_one_attachment(
                source,
                index=index,
                policy=policy,
                client=client,
                resolver=resolver,
                remaining_bytes=policy.max_total_bytes - total_bytes,
                deadline=deadline,
            )
            downloaded.append(attachment)
            total_bytes += len(attachment.data)
    finally:
        if owns_client:
            client.close()
    return downloaded


def build_message(
    *,
    sender_address,
    sender_name,
    normalized_to,
    normalized_cc,
    subject,
    body,
    in_reply_to,
    references,
    attachments,
):
    message = EmailMessage()
    message["From"] = str(
        Address(display_name=sender_name, addr_spec=sender_address)
    )
    if normalized_to:
        message["To"] = ", ".join(normalized_to)
    if normalized_cc:
        message["Cc"] = ", ".join(normalized_cc)
    message["Subject"] = subject
    message["Date"] = formatdate(localtime=True)
    message_id = make_msgid(domain=sender_address.rsplit("@", 1)[1])
    message["Message-ID"] = message_id
    if in_reply_to:
        message["In-Reply-To"] = validate_header(in_reply_to, "In-Reply-To", 998)
    if references:
        message["References"] = validate_header(references, "References", 4096)
    message.set_content(body)
    for attachment in attachments:
        maintype, subtype = attachment.mime_type.split("/", 1)
        message.add_attachment(
            attachment.data,
            maintype=maintype,
            subtype=subtype,
            filename=attachment.file_name,
            disposition="attachment",
        )
    return message, message_id


def serialize_message(message, maximum_bytes=None):
    raw_message = message.as_bytes(policy=email.policy.SMTP)
    if maximum_bytes is not None and len(raw_message) > maximum_bytes:
        raise AttachmentError("The encoded email exceeds the message size limit.")
    return raw_message


def submit_smtp_message(
    *,
    host,
    port,
    username,
    password,
    sender_address,
    recipients,
    raw_message,
    smtp_factory=smtplib.SMTP,
):
    smtp_client = None
    submission_started = False
    try:
        smtp_client = smtp_factory(host, port, timeout=15)
        smtp_client.ehlo()
        smtp_client.starttls(context=ssl.create_default_context())
        smtp_client.ehlo()
        smtp_client.login(username, password)
        submission_started = True
        return smtp_client.sendmail(sender_address, recipients, raw_message)
    except (
        smtplib.SMTPAuthenticationError,
        smtplib.SMTPHeloError,
        smtplib.SMTPNotSupportedError,
        smtplib.SMTPSenderRefused,
        smtplib.SMTPRecipientsRefused,
        smtplib.SMTPDataError,
    ):
        raise SMTPDeliveryError("SMTP delivery was rejected.") from None
    except (OSError, smtplib.SMTPException):
        if submission_started:
            raise SMTPDeliveryError(
                "SMTP delivery status is uncertain; inspect Sent Mail before retrying.",
                uncertain=True,
            ) from None
        raise SMTPDeliveryError("SMTP delivery failed before submission.") from None
    finally:
        if smtp_client is not None:
            try:
                smtp_client.quit()
            except (OSError, smtplib.SMTPException):
                smtp_client.close()


def attachment_policy_from_args(args):
    return AttachmentPolicy(
        allowed_host_suffixes=tuple(
            normalize_allowed_host(host)
            for host in args.smtp_attachment_allowed_host
        ),
        max_count=args.smtp_max_attachments,
        max_file_bytes=args.smtp_max_attachment_bytes,
        max_total_bytes=args.smtp_max_total_attachment_bytes,
        max_encoded_message_bytes=args.smtp_max_encoded_message_bytes,
        max_redirects=args.smtp_attachment_max_redirects,
        connect_timeout_seconds=args.smtp_attachment_connect_timeout_seconds,
        read_timeout_seconds=args.smtp_attachment_read_timeout_seconds,
        overall_timeout_seconds=args.smtp_attachment_overall_timeout_seconds,
    )


def register_send_tool(server, args):
    sender_address = normalize_address(args.smtp_sender_address)
    attachment_policy = (
        attachment_policy_from_args(args) if args.smtp_attachments_enabled else None
    )
    send_times = deque()
    send_lock = Lock()

    def reserve_send():
        now = time.monotonic()
        with send_lock:
            while send_times and send_times[0] <= now - 3600:
                send_times.popleft()
            if len(send_times) >= args.smtp_max_messages_per_hour:
                raise RuntimeError(
                    "The hourly email sending limit has been reached. Try again later."
                )
            send_times.append(now)
        return now

    def release_send(reservation):
        with send_lock:
            try:
                send_times.remove(reservation)
            except ValueError:
                pass

    def send_email_impl(
        *,
        to,
        subject,
        body,
        cc,
        bcc,
        in_reply_to,
        references,
        attachment_sources,
    ):
        normalized_to = [normalize_address(value) for value in to]
        normalized_cc = [normalize_address(value) for value in (cc or [])]
        normalized_bcc = [normalize_address(value) for value in (bcc or [])]
        recipients = normalize_recipients(
            normalized_to,
            normalized_cc,
            normalized_bcc,
            args.smtp_max_recipients,
        )
        validate_header(subject, "Subject", args.smtp_max_subject_chars)
        if len(body) > args.smtp_max_body_chars:
            raise ValueError(
                f"Body must be at most {args.smtp_max_body_chars} characters."
            )

        attachments = (
            download_attachments(attachment_sources, attachment_policy)
            if attachment_policy is not None
            else []
        )
        message, message_id = build_message(
            sender_address=sender_address,
            sender_name=args.smtp_sender_name,
            normalized_to=normalized_to,
            normalized_cc=normalized_cc,
            subject=subject,
            body=body,
            in_reply_to=in_reply_to,
            references=references,
            attachments=attachments,
        )
        raw_message = serialize_message(
            message,
            attachment_policy.max_encoded_message_bytes
            if attachment_policy is not None
            else None,
        )

        password = Path(args.smtp_password_file).read_text().strip()
        if not password:
            raise RuntimeError("The SMTP credential file is empty.")

        reservation = reserve_send()
        try:
            refused = submit_smtp_message(
                host=args.smtp_host,
                port=args.smtp_port,
                username=args.smtp_username,
                password=password,
                sender_address=sender_address,
                recipients=recipients,
                raw_message=raw_message,
            )
        except SMTPDeliveryError as error:
            if not error.uncertain:
                release_send(reservation)
            raise

        refused_addresses = sorted(refused)
        return {
            "status": "sent" if not refused_addresses else "partially_sent",
            "message_id": message_id,
            "recipient_count": len(recipients),
            "refused_recipients": refused_addresses,
            "attachment_count": len(attachments),
            "total_attachment_bytes": sum(
                len(attachment.data) for attachment in attachments
            ),
            "encoded_message_bytes": len(raw_message),
            "attachments": [attachment.result() for attachment in attachments],
        }

    tool_options = {
        "name": "send_email",
        "annotations": ToolAnnotations(
            title="Send email",
            readOnlyHint=False,
            destructiveHint=True,
            idempotentHint=False,
            openWorldHint=True,
        ),
        "auth": require_scopes(args.smtp_send_scope),
        "timeout": 90 if attachment_policy is not None else 30,
    }

    if attachment_policy is not None:

        @server.tool(
            **tool_options,
            meta={"openai/fileParams": ["attachments"]},
        )
        def send_email(
            to: list[str],
            subject: str,
            body: str,
            cc: list[str] | None = None,
            bcc: list[str] | None = None,
            in_reply_to: str | None = None,
            references: str | None = None,
            attachments: list[ChatGPTFile] = [],
        ) -> dict:
            """Send a plain-text email, optionally with ChatGPT-managed files.

            This immediately performs an external side effect. Before calling,
            show the user the final recipients, subject, complete body, and
            attachment filenames and obtain confirmation. A temporary local file
            must first be materialized by ChatGPT as a managed file; never pass a
            local filesystem path. HTML and inline images are unsupported.

            Args:
                to: Primary recipient email addresses, without display names.
                subject: Message subject.
                body: Plain-text message body.
                cc: Optional carbon-copy recipient addresses.
                bcc: Optional blind-carbon-copy recipient addresses.
                in_reply_to: Optional Message-ID of the message being answered.
                references: Optional space-separated Message-ID reply chain.
                attachments: Optional ChatGPT-managed files to attach.
            """
            return send_email_impl(
                to=to,
                subject=subject,
                body=body,
                cc=cc,
                bcc=bcc,
                in_reply_to=in_reply_to,
                references=references,
                attachment_sources=attachments,
            )

    else:

        @server.tool(**tool_options)
        def send_email(
            to: list[str],
            subject: str,
            body: str,
            cc: list[str] | None = None,
            bcc: list[str] | None = None,
            in_reply_to: str | None = None,
            references: str | None = None,
        ) -> dict:
            """Send a plain-text email through the configured iCloud account.

            This immediately performs an external side effect. Show the user the
            final recipients, subject, and body and obtain confirmation before
            calling it. Attachments and HTML are unsupported.
            """
            return send_email_impl(
                to=to,
                subject=subject,
                body=body,
                cc=cc,
                bcc=bcc,
                in_reply_to=in_reply_to,
                references=references,
                attachment_sources=[],
            )


def main():
    args = parse_args()
    supported_scopes = list(
        dict.fromkeys([*args.required_scope, *args.supported_scope])
    )
    verifier = JWTVerifier(
        jwks_uri=args.jwks_uri,
        issuer=args.issuer,
        audience=args.audience,
        algorithm="RS256",
        required_scopes=args.required_scope,
        ssrf_safe=True,
    )
    auth = RemoteAuthProvider(
        token_verifier=verifier,
        authorization_servers=[AnyHttpUrl(args.issuer)],
        base_url=args.public_url,
        resource_base_url=args.public_url,
        scopes_supported=supported_scopes,
        resource_name="iCloud Mail",
    )
    backend = ProxyClient(
        StdioTransport(command=args.backend_command, args=[]),
        roots=None,
        sampling_handler=None,
        elicitation_handler=None,
    )
    server = create_proxy(backend, name="iCloud Mail", auth=auth)
    if args.smtp_host:
        register_send_tool(server, args)
    server.run(
        transport="streamable-http",
        host=args.listen_address,
        port=args.port,
        path=args.path,
        show_banner=False,
    )


if __name__ == "__main__":
    main()
