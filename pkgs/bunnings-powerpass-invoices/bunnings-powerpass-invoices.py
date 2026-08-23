#!/usr/bin/env python3

from __future__ import annotations

import argparse
import asyncio
import fcntl
import getpass
import json
import os
import re
import signal
import shutil
import subprocess
import sys
import threading
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from urllib.parse import urljoin, urlsplit

from fastmcp import FastMCP
from fastmcp.resources import ResourceContent, ResourceResult
from fastmcp.utilities.types import File
from playwright.sync_api import (
    Browser,
    BrowserContext,
    Error as PlaywrightError,
    Page,
    Playwright,
    TimeoutError as PlaywrightTimeoutError,
    sync_playwright,
)


PORTAL_URL = "https://www.bunningspowerpass.com.au/pwrpass/f?p=111:30"
LOGIN_URL = "https://www.bunningspowerpass.com.au/pwrpass/f?p=111:PP_LOGIN"
PORTAL_HOST = "www.bunningspowerpass.com.au"
DEFAULT_ONEPASSWORD_ITEM = "o4mapnpvcr5cvwx4u5qjhwy62a"
DATE_FORMAT = "%d/%m/%Y"
INVOICE_NUMBER_RE = re.compile(r"^\d{4}/\d+$")
DATE_RE = re.compile(r"^\d{2}/\d{2}/\d{4}$")
INVOICE_ID_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})_(\d{4})-(\d+)\.pdf$")


class UserError(RuntimeError):
    pass


class AuthenticationRequired(UserError):
    pass


@dataclass(frozen=True)
class Transaction:
    invoice_number: str
    transaction_date: str
    transaction_type: str
    url: str

    @property
    def filename(self) -> str:
        date = datetime.strptime(self.transaction_date, DATE_FORMAT)
        safe_number = self.invoice_number.replace("/", "-")
        return f"{date:%Y-%m-%d}_{safe_number}.pdf"


@dataclass
class Session:
    context: BrowserContext
    page: Page
    browser: Browser | None = None
    owns_context: bool = False
    owns_page: bool = False

    def close(self) -> None:
        if self.owns_context:
            self.context.close()
        elif self.owns_page:
            self.page.close()


def default_profile_dir() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    if state_home:
        return Path(state_home) / "bunnings-powerpass-invoices" / "chromium"
    return Path.home() / ".local" / "state" / "bunnings-powerpass-invoices" / "chromium"


def parse_date(value: str) -> datetime:
    try:
        return datetime.strptime(value, DATE_FORMAT)
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            f"expected a real date in DD/MM/YYYY format, got {value!r}"
        ) from error


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="bunnings-powerpass-invoices",
        description=(
            "Download individual tax-invoice PDFs from the Bunnings PowerPass portal. "
            "Run 'login' once for the managed profile, then use 'fetch' headlessly."
        ),
    )
    parser.add_argument(
        "--profile",
        type=Path,
        default=default_profile_dir(),
        help="Playwright Chromium profile (default: %(default)s)",
    )
    parser.add_argument(
        "--cdp-url",
        metavar="URL",
        help=(
            "attach to an already-running Chromium CDP endpoint instead of launching "
            "the managed profile"
        ),
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        metavar="SECONDS",
        help="browser and request timeout (default: %(default)s)",
    )
    parser.add_argument(
        "--onepassword-item",
        default=DEFAULT_ONEPASSWORD_ITEM,
        metavar="ITEM",
        help="1Password login item used for automatic reauthentication",
    )
    parser.add_argument(
        "--credentials-file",
        type=Path,
        metavar="FILE",
        help="read the username and password from the first two lines of FILE",
    )
    parser.add_argument(
        "--session-only",
        action="store_true",
        help="never load credentials; fail when the retained session cannot renew",
    )

    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser(
        "login",
        help="open a visible managed browser and retain its authenticated session",
    )
    commands.add_parser(
        "login-cli",
        help="renew a headless profile using non-echoing terminal prompts",
    )
    commands.add_parser(
        "auth-check",
        help="verify or renew the PowerPass session without downloading invoices",
    )
    commands.add_parser(
        "auth-session",
        help="keep an authentication challenge open and read its SMS code from stdin",
    )
    browser_daemon = commands.add_parser(
        "browser-daemon",
        help="keep the managed Chromium profile running for CDP clients",
    )
    browser_daemon.add_argument(
        "--listen-address",
        default="127.0.0.1",
        help="DevTools address (default: %(default)s)",
    )
    browser_daemon.add_argument(
        "--port",
        type=int,
        default=9223,
        help="DevTools port (default: %(default)s)",
    )
    commands.add_parser(
        "mcp",
        help="serve read-only invoice tools and resources over MCP stdio",
    )

    fetch = commands.add_parser(
        "fetch",
        help="search transactions and download each invoice PDF",
    )
    fetch.add_argument(
        "--from",
        dest="from_date",
        type=parse_date,
        metavar="DD/MM/YYYY",
        help="first transaction date; requires --to",
    )
    fetch.add_argument(
        "--to",
        dest="to_date",
        type=parse_date,
        metavar="DD/MM/YYYY",
        help="last transaction date; requires --from",
    )
    fetch.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("bunnings-invoices"),
        help="invoice directory (default: %(default)s)",
    )
    fetch.add_argument(
        "--headed",
        action="store_true",
        help="show the managed browser while fetching",
    )
    fetch.add_argument(
        "--dry-run",
        action="store_true",
        help="list the invoices without downloading them",
    )
    fetch.add_argument(
        "--force",
        action="store_true",
        help="replace existing invoice files",
    )
    return parser


def validate_args(args: argparse.Namespace, parser: argparse.ArgumentParser) -> None:
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.command == "login" and args.cdp_url:
        parser.error(
            f"{args.command} manages its own profile and cannot be combined with --cdp-url"
        )
    if args.command == "browser-daemon":
        if args.cdp_url:
            parser.error("browser-daemon cannot be combined with --cdp-url")
        if not 1 <= args.port <= 65535:
            parser.error("browser-daemon --port must be between 1 and 65535")
    if args.command != "fetch":
        return
    if (args.from_date is None) != (args.to_date is None):
        parser.error("--from and --to must be provided together")
    if args.from_date and args.from_date > args.to_date:
        parser.error("--from must not be later than --to")


def find_powerpass_page(context: BrowserContext) -> Page | None:
    for page in context.pages:
        if PORTAL_HOST in page.url:
            return page
    return None


def open_session(
    playwright: Playwright,
    *,
    profile: Path,
    cdp_url: str | None,
    headed: bool,
) -> Session:
    if cdp_url:
        browser = playwright.chromium.connect_over_cdp(cdp_url)
        if not browser.contexts:
            raise UserError(f"the CDP endpoint at {cdp_url} has no browser context")
        context = browser.contexts[0]
        page = find_powerpass_page(context)
        owns_page = page is None
        if page is None:
            page = context.new_page()
        return Session(
            browser=browser,
            context=context,
            page=page,
            owns_page=owns_page,
        )

    profile = profile.expanduser().resolve()
    profile.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        profile.chmod(0o700)
    except OSError:
        pass
    context = playwright.chromium.launch_persistent_context(
        str(profile),
        headless=not headed,
        channel="chromium",
        accept_downloads=False,
    )
    page = find_powerpass_page(context)
    if page is None:
        page = context.new_page()
    return Session(context=context, page=page, owns_context=True)


def is_transactions_page(page: Page) -> bool:
    return page.get_by_role("button", name="Search", exact=True).count() > 0


def goto_transactions(page: Page, timeout_ms: int) -> None:
    page.goto(PORTAL_URL, wait_until="domcontentloaded", timeout=timeout_ms)


def onepassword_executable() -> str:
    wrapper = Path("/run/wrappers/bin/op")
    if wrapper.is_file() and os.access(wrapper, os.X_OK):
        return str(wrapper)

    fallback = os.environ.get("POWERPASS_OP_FALLBACK")
    if fallback and Path(fallback).is_file():
        return fallback

    executable = shutil.which("op")
    if executable:
        return executable
    raise UserError("1Password CLI is unavailable")


def credentials_from_onepassword(item: str, timeout_seconds: int) -> tuple[str, str]:
    try:
        result = subprocess.run(
            [
                onepassword_executable(),
                "item",
                "get",
                item,
                "--format",
                "json",
                "--reveal",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise UserError("timed out waiting for 1Password") from error

    if result.returncode != 0:
        raise UserError(
            "could not read the PowerPass credentials from 1Password; "
            "unlock 1Password or configure an op service account"
        )

    try:
        item_data = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise UserError("1Password returned invalid item data") from error

    username = None
    password = None
    for field in item_data.get("fields", []):
        field_id = field.get("id")
        label = field.get("label")
        purpose = field.get("purpose")
        if field_id == "username" or label == "username" or purpose == "USERNAME":
            username = field.get("value")
        elif field_id == "password" or label == "password" or purpose == "PASSWORD":
            password = field.get("value")

    if not isinstance(username, str) or not username:
        raise UserError("the 1Password item has no username")
    if not isinstance(password, str) or not password:
        raise UserError("the 1Password item has no password")
    return username, password


def credentials_from_terminal() -> tuple[str, str]:
    if not sys.stdin.isatty():
        raise UserError("interactive credential entry requires a terminal")
    username = input("Bunnings username: ").strip()
    password = getpass.getpass("Bunnings password: ")
    if not username:
        raise UserError("no Bunnings username was provided")
    if not password:
        raise UserError("no Bunnings password was provided")
    return username, password


def credentials_from_file(path: Path) -> tuple[str, str]:
    try:
        values = path.read_text().splitlines()
    except OSError as error:
        raise UserError(f"could not read the credential file: {error}") from error
    if len(values) != 2 or not values[0] or not values[1]:
        raise UserError(
            "the credential file must contain a username and password on two lines"
        )
    return values[0], values[1]


def auth_stage(page: Page) -> str | None:
    if is_transactions_page(page):
        return "authenticated"

    username = page.locator("#username:visible")
    password = page.locator("#password:visible")
    if username.count() > 0 and password.count() > 0:
        return "credentials"

    if page.locator("#securityCode:visible").count() > 0:
        return "interaction-required"
    if page.locator("input[autocomplete='one-time-code']:visible").count() > 0:
        return "interaction-required"

    current = urlsplit(page.url)
    if current.hostname == PORTAL_HOST and "PP_LOGIN" not in current.path.upper():
        if "PP_LOGIN" not in page.url.upper():
            return "portal"
    return None


def wait_for_auth_stage(page: Page, timeout_ms: int) -> str:
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        stage = auth_stage(page)
        if stage:
            return stage
        page.wait_for_timeout(250)
    return "interaction-required"


def finish_portal_authentication(page: Page, timeout_ms: int) -> bool:
    goto_transactions(page, timeout_ms)
    return is_transactions_page(page)


def finish_post_login_interstitial(page: Page, timeout_ms: int) -> bool:
    authentication_fields = (
        "#username:visible, #password:visible, #securityCode:visible, "
        "input[autocomplete='one-time-code']:visible"
    )
    if page.locator(authentication_fields).count() > 0:
        return False
    return finish_portal_authentication(page, timeout_ms)


def interaction_summary(page: Page) -> str:
    title = page.title().strip() or "untitled page"
    input_names = []
    for field in page.locator("input:visible").all():
        name = field.get_attribute("name") or field.get_attribute("id")
        field_type = field.get_attribute("type") or "text"
        input_names.append(f"{name or 'unnamed'}:{field_type}")
    inputs = ", ".join(input_names) if input_names else "none"
    return f"{title!r}; visible inputs: {inputs}"


def ensure_authenticated(
    page: Page,
    args: argparse.Namespace,
    timeout_ms: int,
    *,
    allow_interaction: bool = False,
    interactive_credentials: bool = False,
) -> bool:
    goto_transactions(page, timeout_ms)
    if is_transactions_page(page):
        return True

    page.goto(LOGIN_URL, wait_until="domcontentloaded", timeout=timeout_ms)
    sign_in = page.get_by_role("button", name="Sign in to PowerPass", exact=True)
    if sign_in.count() == 0:
        raise UserError("could not find the PowerPass sign-in entrypoint")
    sign_in.click(timeout=timeout_ms)

    stage = wait_for_auth_stage(page, timeout_ms)
    if stage == "authenticated":
        return True
    if stage == "portal" and finish_portal_authentication(page, timeout_ms):
        return True
    if finish_post_login_interstitial(page, timeout_ms):
        return True

    if stage == "credentials":
        if args.session_only:
            raise AuthenticationRequired(
                "the retained PowerPass session requires operator renewal"
            )
        if args.credentials_file:
            username, password = credentials_from_file(args.credentials_file)
        elif interactive_credentials:
            username, password = credentials_from_terminal()
        else:
            username, password = credentials_from_onepassword(
                args.onepassword_item, args.timeout
            )
        username_field = page.locator("#username:visible")
        password_field = page.locator("#password:visible")
        username_field.fill(username, timeout=timeout_ms)
        password_field.fill(password, timeout=timeout_ms)

        remember_me = page.locator("#rememberMe:visible")
        if remember_me.count() > 0:
            remember_me.check(timeout=timeout_ms)

        login_form = username_field.locator("xpath=ancestor::form[1]")
        submit = login_form.get_by_role("button", name="Sign in", exact=True)
        if submit.count() == 0:
            raise UserError("could not find the Bunnings credential submit button")
        submit.click(timeout=timeout_ms)
        page.wait_for_timeout(750)

        stage = wait_for_auth_stage(page, timeout_ms)
        if stage == "authenticated":
            return True
        if stage == "portal" and finish_portal_authentication(page, timeout_ms):
            return True
        if finish_post_login_interstitial(page, timeout_ms):
            return True
        if stage == "credentials":
            raise UserError("Bunnings rejected the stored credentials")

    trusted_device = page.locator("#trustedDevice:visible")
    if trusted_device.count() > 0:
        trusted_device.check(timeout=timeout_ms)
    if allow_interaction:
        return False

    location = urlsplit(page.url).hostname or "the identity provider"
    raise AuthenticationRequired(
        f"interactive authentication is required at {location} "
        f"({interaction_summary(page)}); "
        "open the managed profile with the 'login' command"
    )


def login(args: argparse.Namespace) -> None:
    timeout_ms = args.timeout * 1000
    with sync_playwright() as playwright:
        session = open_session(
            playwright,
            profile=args.profile,
            cdp_url=None,
            headed=True,
        )
        try:
            if ensure_authenticated(
                session.page,
                args,
                timeout_ms,
                allow_interaction=True,
            ):
                print(f"PowerPass is authenticated in {args.profile}.")
                return

            print(
                "Complete the security-code or other authentication challenge "
                "in the managed browser window. This device has been marked trusted."
            )
            input("When authentication is complete, press Enter here to verify it...")
            goto_transactions(session.page, timeout_ms)
            if not is_transactions_page(session.page):
                raise UserError(
                    "PowerPass still does not show the Transactions search page"
                )
            print(f"Authenticated session retained in {args.profile}.")
        finally:
            session.close()


def login_cli(args: argparse.Namespace) -> None:
    timeout_ms = args.timeout * 1000
    with sync_playwright() as playwright:
        session = open_session(
            playwright,
            profile=args.profile,
            cdp_url=args.cdp_url,
            headed=False,
        )
        try:
            if ensure_authenticated(
                session.page,
                args,
                timeout_ms,
                allow_interaction=True,
                interactive_credentials=True,
            ):
                print(f"PowerPass is authenticated in {args.profile}.")
                return

            if session.page.locator("#securityCode:visible").count() == 0:
                if finish_post_login_interstitial(session.page, timeout_ms):
                    print(f"Authenticated trusted session retained in {args.profile}.")
                    return
                raise UserError(
                    f"unsupported interactive challenge ({interaction_summary(session.page)})"
                )
            if not sys.stdin.isatty():
                raise UserError("interactive SMS entry requires a terminal")

            code = getpass.getpass("Bunnings SMS security code: ").strip()
            if not code:
                raise UserError("no SMS security code was provided")
            submit_security_code(session.page, code, timeout_ms)
            print(f"Authenticated trusted session retained in {args.profile}.")
        finally:
            session.close()


def browser_daemon(args: argparse.Namespace) -> None:
    profile = args.profile.expanduser().resolve()
    profile.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        profile.chmod(0o700)
    except OSError:
        pass

    stopping = threading.Event()

    def stop(_signum: int, _frame: object) -> None:
        stopping.set()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    with sync_playwright() as playwright:
        context = playwright.chromium.launch_persistent_context(
            str(profile),
            headless=True,
            channel="chromium",
            accept_downloads=False,
            args=[
                f"--remote-debugging-address={args.listen_address}",
                f"--remote-debugging-port={args.port}",
            ],
        )
        try:
            print(
                f"PowerPass Chromium is listening on "
                f"http://{args.listen_address}:{args.port}.",
                flush=True,
            )
            while not stopping.wait(60):
                pass
        finally:
            try:
                context.close()
            except Exception:
                if not stopping.is_set():
                    raise


def auth_check(args: argparse.Namespace) -> None:
    timeout_ms = args.timeout * 1000
    with sync_playwright() as playwright:
        session = open_session(
            playwright,
            profile=args.profile,
            cdp_url=args.cdp_url,
            headed=False,
        )
        try:
            ensure_authenticated(session.page, args, timeout_ms)
            print("PowerPass authentication is ready.")
        finally:
            session.close()


def submit_security_code(page: Page, code: str, timeout_ms: int) -> None:
    if not re.fullmatch(r"\d{6}", code):
        raise UserError("the SMS security code must contain exactly six digits")

    security_code = page.locator("#securityCode:visible")
    if security_code.count() == 0:
        raise UserError("there is no active SMS security-code challenge")

    trusted_device = page.locator("#trustedDevice:visible")
    if trusted_device.count() > 0:
        trusted_device.check(timeout=timeout_ms)
    security_code.fill(code, timeout=timeout_ms)

    challenge_form = security_code.locator("xpath=ancestor::form[1]")
    verify = challenge_form.get_by_role("button", name="Verify", exact=True)
    if verify.count() == 0:
        raise UserError("could not find the SMS security-code submit button")
    verify.click(timeout=timeout_ms)
    page.wait_for_timeout(750)

    stage = wait_for_auth_stage(page, timeout_ms)
    if stage == "authenticated":
        return
    if stage == "portal" and finish_portal_authentication(page, timeout_ms):
        return
    if finish_post_login_interstitial(page, timeout_ms):
        return
    if stage == "interaction-required" and security_code.count() > 0:
        raise UserError("Bunnings rejected or expired the SMS security code")
    raise UserError(f"authentication did not complete ({interaction_summary(page)})")


def auth_session(args: argparse.Namespace) -> None:
    timeout_ms = args.timeout * 1000
    with sync_playwright() as playwright:
        session = open_session(
            playwright,
            profile=args.profile,
            cdp_url=args.cdp_url,
            headed=False,
        )
        try:
            if ensure_authenticated(
                session.page,
                args,
                timeout_ms,
                allow_interaction=True,
            ):
                print("AUTHENTICATED", flush=True)
                return

            if session.page.locator("#securityCode:visible").count() == 0:
                if finish_post_login_interstitial(session.page, timeout_ms):
                    print("AUTHENTICATED", flush=True)
                    return
                raise UserError(
                    f"unsupported interactive challenge ({interaction_summary(session.page)})"
                )

            print("SMS_REQUIRED", flush=True)
            if sys.stdin.isatty():
                code = getpass.getpass("SMS security code: ").strip()
            else:
                code = sys.stdin.readline().strip()
            if not code:
                raise UserError("no SMS security code was provided")

            submit_security_code(session.page, code, timeout_ms)
            print("AUTHENTICATED", flush=True)
        finally:
            session.close()


def configure_search(
    page: Page,
    from_date: datetime | None,
    to_date: datetime | None,
    timeout_ms: int,
) -> None:
    if from_date is None:
        page.get_by_role(
            "radio", name="Transactions from current month", exact=True
        ).check(timeout=timeout_ms)
    else:
        page.get_by_role(
            "radio", name="Date Range (Format: DD/MM/YYYY)", exact=True
        ).check(timeout=timeout_ms)
        from_field = page.get_by_label("From", exact=True)
        from_field.fill(from_date.strftime(DATE_FORMAT), timeout=timeout_ms)
        from_field.press("Escape", timeout=timeout_ms)
        to_field = page.get_by_label("To", exact=True)
        to_field.fill(to_date.strftime(DATE_FORMAT), timeout=timeout_ms)
        to_field.press("Escape", timeout=timeout_ms)

    search = page.get_by_role("button", name="Search", exact=True)
    with page.expect_navigation(wait_until="domcontentloaded", timeout=timeout_ms):
        search.click(timeout=timeout_ms)


def transactions_on_page(page: Page) -> list[Transaction]:
    transactions: list[Transaction] = []
    for link in page.locator("table a").all():
        text = (link.text_content() or "").strip()
        if not INVOICE_NUMBER_RE.fullmatch(text):
            continue
        href = link.get_attribute("href")
        if not href:
            continue
        cells = [
            value.strip()
            for value in link.locator("xpath=ancestor::tr[1]")
            .locator("td")
            .all_text_contents()
        ]
        date_index = next(
            (index for index, value in enumerate(cells) if DATE_RE.fullmatch(value)),
            None,
        )
        if date_index is None:
            raise UserError(f"could not find a transaction date for invoice {text}")
        transaction_type = cells[date_index - 1] if date_index > 0 else "Invoice"
        transactions.append(
            Transaction(
                invoice_number=text,
                transaction_date=cells[date_index],
                transaction_type=transaction_type,
                url=urljoin(page.url, href),
            )
        )
    return transactions


def next_report_page(page: Page, timeout_ms: int) -> bool:
    pagination_text = page.locator(".t-Report-paginationText")
    if pagination_text.count() == 0:
        return False
    old_range = (pagination_text.first.text_content() or "").strip()
    pager = pagination_text.first.locator("xpath=ancestor::table[1]")
    cells = pager.locator("td.pagination").all()
    current_cell = next(
        (
            index
            for index, cell in enumerate(cells)
            if cell.locator(".t-Report-paginationText").count() > 0
        ),
        None,
    )
    if current_cell is None:
        return False

    for cell in cells[current_cell + 1 :]:
        links = cell.locator("a")
        if links.count() == 0:
            continue
        links.first.click(timeout=timeout_ms)
        page.wait_for_function(
            "oldRange => document.querySelector('.t-Report-paginationText')?.textContent.trim() !== oldRange",
            arg=old_range,
            timeout=timeout_ms,
        )
        return True
    return False


def collect_transactions(page: Page, timeout_ms: int) -> list[Transaction]:
    result: list[Transaction] = []
    seen: set[tuple[str, str]] = set()
    while True:
        page_transactions = transactions_on_page(page)
        for transaction in page_transactions:
            key = (transaction.invoice_number, transaction.transaction_date)
            if key not in seen:
                seen.add(key)
                result.append(transaction)
        if not next_report_page(page, timeout_ms):
            break
    return result


def download_invoice_bytes(
    context: BrowserContext,
    transaction: Transaction,
    timeout_ms: int,
) -> bytes:
    response = context.request.get(
        transaction.url,
        fail_on_status_code=False,
        timeout=timeout_ms,
    )
    try:
        body = response.body()
        content_type = response.headers.get("content-type", "")
        if response.status != 200:
            raise UserError(
                f"invoice {transaction.invoice_number} returned HTTP {response.status}"
            )
        if not body.startswith(b"%PDF-"):
            raise UserError(
                f"invoice {transaction.invoice_number} returned {content_type or 'non-PDF data'}"
            )

        return body
    finally:
        response.dispose()


def download_invoice(
    context: BrowserContext,
    transaction: Transaction,
    destination: Path,
    timeout_ms: int,
) -> None:
    body = download_invoice_bytes(context, transaction, timeout_ms)
    temporary = destination.with_name(f".{destination.name}.{os.getpid()}.tmp")
    try:
        temporary.write_bytes(body)
        temporary.chmod(0o600)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def queried_transactions(
    args: argparse.Namespace,
    from_date: datetime | None,
    to_date: datetime | None,
) -> list[Transaction]:
    timeout_ms = args.timeout * 1000
    with sync_playwright() as playwright:
        session = open_session(
            playwright,
            profile=args.profile,
            cdp_url=args.cdp_url,
            headed=False,
        )
        try:
            ensure_authenticated(session.page, args, timeout_ms)
            configure_search(session.page, from_date, to_date, timeout_ms)
            return collect_transactions(session.page, timeout_ms)
        finally:
            session.close()


def authentication_ready(args: argparse.Namespace) -> None:
    timeout_ms = args.timeout * 1000
    with sync_playwright() as playwright:
        session = open_session(
            playwright,
            profile=args.profile,
            cdp_url=args.cdp_url,
            headed=False,
        )
        try:
            ensure_authenticated(session.page, args, timeout_ms)
        finally:
            session.close()


def invoice_resource_uri(transaction: Transaction) -> str:
    return f"powerpass://invoice/{transaction.filename}"


def transaction_record(transaction: Transaction) -> dict[str, str]:
    return {
        "invoice_number": transaction.invoice_number,
        "transaction_date": transaction.transaction_date,
        "transaction_type": transaction.transaction_type,
        "invoice_id": transaction.filename,
        "filename": transaction.filename,
        "resource_uri": invoice_resource_uri(transaction),
    }


def parse_mcp_date(value: str | None, name: str) -> datetime | None:
    if value is None:
        return None
    try:
        return datetime.strptime(value, DATE_FORMAT)
    except ValueError as error:
        raise UserError(f"{name} must be a real date in DD/MM/YYYY format") from error


class McpBackend:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.args.session_only = True
        self.lock = threading.Lock()
        self.browser_lock_path = args.profile.parent / "browser.lock"

    @contextmanager
    def browser_access(self) -> Iterator[None]:
        with self.lock:
            self.browser_lock_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            with self.browser_lock_path.open("a") as lock_file:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
                try:
                    yield
                finally:
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def authentication_status(self) -> dict[str, str]:
        with self.browser_access():
            try:
                authentication_ready(self.args)
            except AuthenticationRequired:
                return {
                    "status": "authentication_required",
                    "message": "An operator must renew the trusted session over SSH.",
                }
            return {"status": "ready", "message": "PowerPass authentication is ready."}

    def list_invoices(
        self, from_date_text: str | None, to_date_text: str | None
    ) -> dict[str, object]:
        from_date = parse_mcp_date(from_date_text, "from_date")
        to_date = parse_mcp_date(to_date_text, "to_date")
        if (from_date is None) != (to_date is None):
            raise UserError("from_date and to_date must be provided together")
        if from_date and to_date and from_date > to_date:
            raise UserError("from_date must not be later than to_date")

        with self.browser_access():
            try:
                transactions = queried_transactions(self.args, from_date, to_date)
            except AuthenticationRequired:
                return {
                    "status": "authentication_required",
                    "message": "An operator must renew the trusted session over SSH.",
                    "invoices": [],
                }
        return {
            "status": "ready",
            "count": len(transactions),
            "invoices": [transaction_record(item) for item in transactions],
        }

    def read_invoice(self, invoice_id: str) -> bytes:
        match = INVOICE_ID_RE.fullmatch(invoice_id)
        if not match:
            raise UserError("invoice_id must look like YYYY-MM-DD_1234-5678.pdf")
        date = datetime.strptime(match.group(1), "%Y-%m-%d")
        wanted_filename = invoice_id
        timeout_ms = self.args.timeout * 1000

        with self.browser_access():
            with sync_playwright() as playwright:
                session = open_session(
                    playwright,
                    profile=self.args.profile,
                    cdp_url=self.args.cdp_url,
                    headed=False,
                )
                try:
                    ensure_authenticated(session.page, self.args, timeout_ms)
                    configure_search(session.page, date, date, timeout_ms)
                    transactions = collect_transactions(session.page, timeout_ms)
                    transaction = next(
                        (
                            item
                            for item in transactions
                            if item.filename == wanted_filename
                        ),
                        None,
                    )
                    if transaction is None:
                        raise UserError(f"invoice {invoice_id!r} was not found")
                    return download_invoice_bytes(
                        session.context, transaction, timeout_ms
                    )
                finally:
                    session.close()


def serve_mcp(args: argparse.Namespace) -> None:
    backend = McpBackend(args)
    server = FastMCP("Bunnings PowerPass Invoices")

    @server.tool(
        name="authentication_status",
        description=(
            "Check whether the retained trusted PowerPass browser session can be used. "
            "This never accepts or retrieves credentials or MFA codes."
        ),
        annotations={
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": True,
        },
    )
    def authentication_status() -> dict[str, str]:
        return backend.authentication_status()

    @server.tool(
        name="list_invoices",
        description=(
            "List PowerPass tax invoices for the current month, or an inclusive date "
            "range when both dates are supplied. Dates use DD/MM/YYYY. Each result "
            "includes an invoice_id for download_invoice and a powerpass:// PDF "
            "resource URI."
        ),
        annotations={
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": True,
        },
    )
    def list_invoices(
        from_date: str | None = None, to_date: str | None = None
    ) -> dict[str, object]:
        return backend.list_invoices(from_date, to_date)

    @server.tool(
        name="download_invoice",
        description=(
            "Download one PowerPass tax invoice as a PDF file. Use the invoice_id "
            "returned by list_invoices."
        ),
        annotations={
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": True,
        },
    )
    async def download_invoice(invoice_id: str) -> File:
        data = await asyncio.to_thread(backend.read_invoice, invoice_id)
        return File(data=data, format="pdf", name=Path(invoice_id).stem)

    @server.resource(
        "powerpass://invoice/{invoice_id}",
        name="PowerPass tax invoice",
        description="A Bunnings PowerPass tax-invoice PDF returned as binary data.",
        mime_type="application/pdf",
    )
    async def invoice_pdf(invoice_id: str) -> ResourceResult:
        data = await asyncio.to_thread(backend.read_invoice, invoice_id)
        return ResourceResult(
            contents=[ResourceContent(content=data, mime_type="application/pdf")]
        )

    server.run(transport="stdio", show_banner=False)


def fetch(args: argparse.Namespace) -> None:
    timeout_ms = args.timeout * 1000
    with sync_playwright() as playwright:
        session = open_session(
            playwright,
            profile=args.profile,
            cdp_url=args.cdp_url,
            headed=args.headed,
        )
        try:
            ensure_authenticated(session.page, args, timeout_ms)

            configure_search(session.page, args.from_date, args.to_date, timeout_ms)
            transactions = collect_transactions(session.page, timeout_ms)
            if not transactions:
                print("No invoice transactions matched the search.")
                return

            print(f"Found {len(transactions)} invoice transaction(s).")
            if args.dry_run:
                for transaction in transactions:
                    print(
                        f"{transaction.transaction_date}\t"
                        f"{transaction.invoice_number}\t"
                        f"{transaction.transaction_type}\t"
                        f"{transaction.filename}"
                    )
                return

            output = args.output.expanduser().resolve()
            output.mkdir(mode=0o700, parents=True, exist_ok=True)
            downloaded = 0
            skipped = 0
            for transaction in transactions:
                destination = output / transaction.filename
                if destination.exists() and not args.force:
                    print(f"skip {destination.name} (already exists)")
                    skipped += 1
                    continue
                download_invoice(
                    session.context,
                    transaction,
                    destination,
                    timeout_ms,
                )
                print(f"saved {destination}")
                downloaded += 1
            print(f"Downloaded {downloaded}; skipped {skipped}.")
        finally:
            session.close()


def main() -> int:
    parser = make_parser()
    args = parser.parse_args()
    validate_args(args, parser)
    try:
        if args.command == "login":
            login(args)
        elif args.command == "login-cli":
            login_cli(args)
        elif args.command == "auth-check":
            auth_check(args)
        elif args.command == "auth-session":
            auth_session(args)
        elif args.command == "browser-daemon":
            browser_daemon(args)
        elif args.command == "mcp":
            serve_mcp(args)
        else:
            fetch(args)
    except (UserError, PlaywrightTimeoutError) as error:
        print(f"bunnings-powerpass-invoices: {error}", file=sys.stderr)
        return 1
    except PlaywrightError as error:
        print(f"bunnings-powerpass-invoices: browser error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("bunnings-powerpass-invoices: interrupted", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
