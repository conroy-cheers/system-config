import asyncio
import email
import hashlib
import smtplib
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

import httpx
from fastmcp import FastMCP

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import gateway


PUBLIC_ADDRESSES = lambda _host: {"8.8.8.8", "2606:4700:4700::1111"}


def policy(**overrides):
    values = {
        "allowed_host_suffixes": ("oaiusercontent.com",),
        "allowed_azure_blob_account_prefixes": (),
        "max_count": 5,
        "max_file_bytes": 1024,
        "max_total_bytes": 2048,
        "max_encoded_message_bytes": 4096,
        "max_redirects": 3,
        "connect_timeout_seconds": 5,
        "read_timeout_seconds": 20,
        "overall_timeout_seconds": 45,
    }
    values.update(overrides)
    return gateway.AttachmentPolicy(**values)


def source(**overrides):
    values = {
        "download_url": "https://files.oaiusercontent.com/download?token=secret",
        "file_id": "file-test",
        "mime_type": "application/pdf",
        "file_name": "report.pdf",
    }
    values.update(overrides)
    return gateway.ChatGPTFile(**values)


class FakeResponse:
    def __init__(self, *, status=200, headers=None, chunks=()):
        self.status_code = status
        self.headers = headers or {}
        self.chunks = chunks

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def raise_for_status(self):
        if self.status_code >= 400:
            request = httpx.Request("GET", "https://redacted.invalid/")
            response = httpx.Response(self.status_code, request=request)
            raise httpx.HTTPStatusError("download failed", request=request, response=response)

    def iter_bytes(self, chunk_size):
        self.chunk_size = chunk_size
        yield from self.chunks


class FakeClient:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.urls = []

    def stream(self, method, url, headers):
        self.urls.append((method, url, headers))
        return next(self.responses)


class FileSchemaTests(unittest.TestCase):
    def test_schema_matches_openai_file_contract(self):
        schema = gateway.ChatGPTFile.model_json_schema()
        self.assertEqual(
            set(schema["properties"]),
            {"download_url", "file_id", "mime_type", "file_name"},
        )
        self.assertEqual(schema["required"], ["download_url", "file_id"])
        self.assertFalse(schema["additionalProperties"])

    def test_optional_metadata_may_be_omitted(self):
        value = gateway.ChatGPTFile(
            download_url="https://files.oaiusercontent.com/download",
            file_id="file-test",
        )
        self.assertEqual(value.mime_type, "")
        self.assertEqual(value.file_name, "")

    def test_registered_tool_declares_attachment_file_parameter(self):
        args = SimpleNamespace(
            smtp_sender_address="sender@example.com",
            smtp_attachments_enabled=True,
            smtp_attachment_allowed_host=["oaiusercontent.com"],
            smtp_attachment_allowed_azure_blob_account_prefix=[],
            smtp_max_attachments=5,
            smtp_max_attachment_bytes=8 * 1024 * 1024,
            smtp_max_total_attachment_bytes=10 * 1024 * 1024,
            smtp_max_encoded_message_bytes=15 * 1024 * 1024,
            smtp_attachment_max_redirects=3,
            smtp_attachment_connect_timeout_seconds=5,
            smtp_attachment_read_timeout_seconds=20,
            smtp_attachment_overall_timeout_seconds=45,
            smtp_max_recipients=20,
            smtp_max_subject_chars=998,
            smtp_max_body_chars=200000,
            smtp_max_messages_per_hour=20,
            smtp_send_scope="mail.send",
        )
        server = FastMCP("test")
        gateway.register_send_tool(server, args)
        tool = asyncio.run(server._local_provider.get_tool("send_email"))
        self.assertEqual(tool.meta, {"openai/fileParams": ["attachments"]})
        attachment_schema = tool.parameters["$defs"]["ChatGPTFile"]
        self.assertEqual(
            set(attachment_schema["properties"]),
            {"download_url", "file_id", "mime_type", "file_name"},
        )
        self.assertEqual(
            attachment_schema["required"], ["download_url", "file_id"]
        )
        self.assertEqual(
            tool.parameters["properties"]["attachments"]["type"], "array"
        )
        self.assertIn("pass the resulting `file_...` identifier", tool.description)
        self.assertIn("Do not pass structured objects", tool.description)

        with self.assertRaises(gateway.ToolError) as raised:
            asyncio.run(
                tool.run(
                    {
                        "to": ["recipient@example.com"],
                        "subject": "Subject",
                        "body": "Body",
                        "attachments": [
                            {
                                "download_url": "https://evil.example/file",
                                "file_id": "file-test",
                            }
                        ],
                    }
                )
            )
        self.assertEqual(
            str(raised.exception), "An attachment download host is not allowed."
        )


class URLValidationTests(unittest.TestCase):
    def test_rejects_overly_broad_allowed_host_suffix(self):
        for host in ("", "com", "files.oaiusercontent.com."):
            with self.subTest(host=host), self.assertRaises(ValueError):
                gateway.normalize_allowed_host(host)

    def test_accepts_allowed_host_and_subdomain(self):
        for host in (
            "files.oaiusercontent.com",
            "sdmntpraustraliaeast.oaiusercontent.com",
        ):
            url = f"https://{host}/file"
            self.assertEqual(
                gateway.validate_download_url(
                    url, ("oaiusercontent.com",), PUBLIC_ADDRESSES
                ),
                url,
            )

    def test_accepts_only_configured_openai_azure_storage_accounts(self):
        for host in (
            "oaisdmntpraustraliaeast.blob.core.windows.net",
            "oaisdmntprindiasocentral.blob.core.windows.net",
        ):
            url = f"https://{host}/file"
            self.assertEqual(
                gateway.validate_download_url(
                    url,
                    ("oaiusercontent.com",),
                    PUBLIC_ADDRESSES,
                    allowed_azure_blob_account_prefixes=("oaisdmntpr",),
                ),
                url,
            )
        for url in (
            "https://another-account.blob.core.windows.net/file",
            "https://evil.oaisdmntpraustraliaeast.blob.core.windows.net/file",
            "https://oaisdmntpraustraliaeast.blob.core.windows.net.evil.example/file",
        ):
            with self.subTest(url=url), self.assertRaises(gateway.AttachmentError):
                gateway.validate_download_url(
                    url,
                    ("oaiusercontent.com",),
                    PUBLIC_ADDRESSES,
                    allowed_azure_blob_account_prefixes=("oaisdmntpr",),
                )

    def test_rejects_overly_broad_azure_storage_account_prefix(self):
        for prefix in ("", "oai", "not-valid", "a" * 25):
            with self.subTest(prefix=prefix), self.assertRaises(ValueError):
                gateway.normalize_allowed_azure_blob_account_prefix(prefix)

    def test_rejects_suffix_confusion_and_unsafe_url_parts(self):
        urls = (
            "https://files.oaiusercontent.com.evil.example/file",
            "http://files.oaiusercontent.com/file",
            "https://user:pass@files.oaiusercontent.com/file",
            "https://files.oaiusercontent.com:8443/file",
            "https://files.oaiusercontent.com/file#fragment",
            "https://127.0.0.1/file",
        )
        for url in urls:
            with self.subTest(url=url), self.assertRaises(gateway.AttachmentError):
                gateway.validate_download_url(
                    url, ("oaiusercontent.com",), PUBLIC_ADDRESSES
                )

    def test_rejects_non_public_dns_results(self):
        for address in ("127.0.0.1", "10.0.0.1", "169.254.169.254", "::1"):
            with self.subTest(address=address), self.assertRaises(
                gateway.AttachmentError
            ):
                gateway.validate_download_url(
                    "https://files.oaiusercontent.com/file",
                    ("oaiusercontent.com",),
                    lambda _host, address=address: {address},
                )


class AttachmentDownloadTests(unittest.TestCase):
    def test_downloads_and_hashes_opaque_bytes(self):
        data = b"hello\x00attachment"
        client = FakeClient(
            [FakeResponse(headers={"content-length": str(len(data))}, chunks=(data,))]
        )
        result = gateway.download_attachments(
            [source()], policy(), client=client, resolver=PUBLIC_ADDRESSES
        )
        self.assertEqual(result[0].data, data)
        self.assertEqual(result[0].sha256, hashlib.sha256(data).hexdigest())
        self.assertEqual(client.urls[0][2], {"Accept": "*/*"})

    def test_validates_redirect_destination(self):
        client = FakeClient(
            [
                FakeResponse(status=302, headers={"location": "https://evil.example/file"}),
                FakeResponse(chunks=(b"should not be read",)),
            ]
        )
        with self.assertRaises(gateway.AttachmentError):
            gateway.download_attachments(
                [source()], policy(), client=client, resolver=PUBLIC_ADDRESSES
            )
        self.assertEqual(len(client.urls), 1)

    def test_enforces_declared_and_streamed_size_limits(self):
        cases = (
            FakeResponse(headers={"content-length": "1025"}, chunks=()),
            FakeResponse(chunks=(b"a" * 700, b"b" * 400)),
        )
        for response in cases:
            with self.subTest(response=response), self.assertRaises(
                gateway.AttachmentError
            ):
                gateway.download_attachments(
                    [source()],
                    policy(max_file_bytes=1024),
                    client=FakeClient([response]),
                    resolver=PUBLIC_ADDRESSES,
                )

    def test_enforces_total_limit_across_files(self):
        client = FakeClient(
            [FakeResponse(chunks=(b"a" * 700,)), FakeResponse(chunks=(b"b" * 400,))]
        )
        with self.assertRaises(gateway.AttachmentError):
            gateway.download_attachments(
                [source(file_id="file-1"), source(file_id="file-2")],
                policy(max_total_bytes=1000),
                client=client,
                resolver=PUBLIC_ADDRESSES,
            )

    def test_rejects_duplicate_file_ids_before_downloading(self):
        client = FakeClient([])
        with self.assertRaises(gateway.AttachmentError):
            gateway.download_attachments(
                [source(), source()], policy(), client=client, resolver=PUBLIC_ADDRESSES
            )
        self.assertEqual(client.urls, [])

    def test_sanitizes_filename_and_falls_back_from_unsafe_mime_type(self):
        item = source(
            file_name="../../bad\r\n\u202etxt.unknown-extension",
            mime_type="multipart/mixed",
        )
        result = gateway.download_attachments(
            [item],
            policy(),
            client=FakeClient([FakeResponse(chunks=(b"data",))]),
            resolver=PUBLIC_ADDRESSES,
        )[0]
        self.assertEqual(result.file_name, "badtxt.unknown-extension")
        self.assertEqual(result.mime_type, "application/octet-stream")


class MessageTests(unittest.TestCase):
    def test_mime_message_round_trips_attachment_and_omits_bcc(self):
        attachment = gateway.DownloadedAttachment(
            file_name="report.pdf",
            mime_type="application/pdf",
            data=b"pdf bytes",
            sha256=hashlib.sha256(b"pdf bytes").hexdigest(),
        )
        message, _message_id = gateway.build_message(
            sender_address="sender@example.com",
            sender_name="Sender",
            normalized_to=["to@example.com"],
            normalized_cc=["cc@example.com"],
            subject="Subject",
            body="Body",
            in_reply_to=None,
            references=None,
            attachments=[attachment],
        )
        parsed = email.message_from_bytes(
            message.as_bytes(policy=email.policy.SMTP), policy=email.policy.default
        )
        self.assertIsNone(parsed["Bcc"])
        self.assertTrue(parsed.is_multipart())
        attached = next(parsed.iter_attachments())
        self.assertEqual(attached.get_filename(), "report.pdf")
        self.assertEqual(attached.get_content_type(), "application/pdf")
        self.assertEqual(attached.get_payload(decode=True), b"pdf bytes")

    def test_rejects_message_after_mime_encoding_exceeds_limit(self):
        message = email.message.EmailMessage()
        message.set_content("body")
        message.add_attachment(
            b"attachment bytes",
            maintype="application",
            subtype="octet-stream",
            filename="attachment.bin",
        )
        encoded = gateway.serialize_message(message)
        with self.assertRaises(gateway.AttachmentError):
            gateway.serialize_message(message, len(encoded) - 1)
        self.assertEqual(gateway.serialize_message(message, len(encoded)), encoded)


class FakeSMTP:
    def __init__(self, _host, _port, timeout):
        self.timeout = timeout
        self.closed = False

    def ehlo(self):
        return 250, b"ok"

    def starttls(self, context):
        self.context = context
        return 220, b"ready"

    def login(self, _username, _password):
        return 235, b"ok"

    def sendmail(self, _sender, _recipients, _message):
        return {}

    def quit(self):
        return 221, b"bye"

    def close(self):
        self.closed = True


class SMTPTests(unittest.TestCase):
    def submit(self, smtp_factory):
        return gateway.submit_smtp_message(
            host="smtp.example.com",
            port=587,
            username="user",
            password="password",
            sender_address="sender@example.com",
            recipients=["to@example.com"],
            raw_message=b"message",
            smtp_factory=smtp_factory,
        )

    def test_submits_exact_serialized_bytes(self):
        captured = {}

        class CapturingSMTP(FakeSMTP):
            def sendmail(self, sender, recipients, message):
                captured.update(sender=sender, recipients=recipients, message=message)
                return {}

        self.assertEqual(self.submit(CapturingSMTP), {})
        self.assertEqual(captured["message"], b"message")

    def test_disconnect_after_submission_starts_is_uncertain(self):
        class DisconnectingSMTP(FakeSMTP):
            def sendmail(self, _sender, _recipients, _message):
                raise smtplib.SMTPServerDisconnected("lost")

        with self.assertRaises(gateway.SMTPDeliveryError) as raised:
            self.submit(DisconnectingSMTP)
        self.assertTrue(raised.exception.uncertain)

    def test_explicit_data_rejection_is_not_uncertain(self):
        class RejectingSMTP(FakeSMTP):
            def sendmail(self, _sender, _recipients, _message):
                raise smtplib.SMTPDataError(552, b"too large")

        with self.assertRaises(gateway.SMTPDeliveryError) as raised:
            self.submit(RejectingSMTP)
        self.assertFalse(raised.exception.uncertain)


if __name__ == "__main__":
    unittest.main()
