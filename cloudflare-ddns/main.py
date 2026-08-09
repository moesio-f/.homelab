import os
import sys
import time

import click
import requests
from cloudflare import APIError, Cloudflare

DEFAULT_IP_PROVIDER = os.environ.get("CF_DDNS_IP_PROVIDER", "https://api.ipify.org")
DEFAULT_INTERVAL = int(os.environ.get("CF_DDNS_INTERVAL_SECONDS", "300"))


def get_public_ip(provider: str = DEFAULT_IP_PROVIDER) -> str:
    """Fetch the host's current public IP address as plain text."""
    response = requests.get(provider, timeout=10)
    response.raise_for_status()
    return response.text.strip()


def get_record(client: Cloudflare, zone_id: str, name: str, record_type: str):
    """Find a DNS record by exact name and type within a zone."""
    records = client.dns.records.list(
        zone_id=zone_id,
        type=record_type,
        name={"exact": name},
    )
    for record in records:
        return record
    return None


def sync_record(
    client: Cloudflare,
    zone_id: str,
    name: str,
    record_type: str,
    ip_address: str,
    ttl: int,
    proxied: bool,
) -> bool:
    """Create or update a single DNS record so it points to ip_address.

    Returns True if a change was made.
    """
    record = get_record(client, zone_id, name, record_type)

    if record is None:
        click.echo(
            f"[cloudflare-ddns] Creating {record_type} record for {name} -> {ip_address}"
        )
        client.dns.records.create(
            zone_id=zone_id,
            type=record_type,
            name=name,
            content=ip_address,
            ttl=ttl,
            proxied=proxied,
        )
        return True

    if record.content == ip_address:
        click.echo(f"[cloudflare-ddns] {name} already up to date ({ip_address})")
        return False

    click.echo(f"[cloudflare-ddns] Updating {name}: {record.content} -> {ip_address}")
    client.dns.records.edit(
        record.id,
        zone_id=zone_id,
        type=record_type,
        name=name,
        content=ip_address,
        ttl=ttl,
        proxied=proxied,
    )
    return True


@click.command()
@click.option(
    "--zone-id",
    envvar="CLOUDFLARE_ZONE_ID",
    required=True,
    help="Cloudflare zone ID that owns the record(s).",
)
@click.option(
    "--record-name",
    envvar="CLOUDFLARE_RECORD_NAME",
    required=True,
    help="Comma-separated DNS record name(s) to keep in sync, e.g. home.example.com.",
)
@click.option(
    "--record-type",
    envvar="CLOUDFLARE_RECORD_TYPE",
    default="A",
    help="DNS record type to manage (A or AAAA).",
)
@click.option(
    "--ttl",
    envvar="CLOUDFLARE_TTL",
    default=300,
    type=int,
    help="TTL to set on managed records (1 = automatic).",
)
@click.option(
    "--proxied",
    envvar="CLOUDFLARE_PROXIED",
    default="true",
    help="Comma-separated proxied flags (true/false) matching record names. A single value applies to all.",
)
@click.option(
    "--ip-provider",
    envvar="CF_DDNS_IP_PROVIDER",
    default=DEFAULT_IP_PROVIDER,
    help="URL that returns the host public IP as plain text.",
)
@click.option(
    "--interval",
    envvar="CF_DDNS_INTERVAL_SECONDS",
    default=DEFAULT_INTERVAL,
    type=int,
    help="Seconds between checks. Ignored when --once is set.",
)
@click.option(
    "--once",
    is_flag=True,
    default=False,
    help="Run a single check-and-update cycle instead of looping forever.",
)
def main(
    zone_id: str,
    record_name: str,
    record_type: str,
    ttl: int,
    proxied: str,
    ip_provider: str,
    interval: int,
    once: bool,
):
    api_token = os.environ.get("CLOUDFLARE_API_TOKEN")
    if not api_token:
        sys.exit("CLOUDFLARE_API_TOKEN environment variable is required.")

    client = Cloudflare(api_token=api_token)
    names = [n.strip() for n in record_name.split(",") if n.strip()]
    proxied_flags = [p.strip().lower() == "true" for p in proxied.split(",")]
    if len(proxied_flags) != len(names):
        proxied_flags = [proxied_flags[0]] * len(names)

    while True:
        try:
            ip_address = get_public_ip(ip_provider)
            for name, rec_proxied in zip(names, proxied_flags):
                sync_record(
                    client, zone_id, name, record_type, ip_address, ttl, rec_proxied
                )
        except APIError as e:
            click.echo(f"[cloudflare-ddns] Cloudflare API error: {e}", err=True)
        except requests.RequestException as e:
            click.echo(
                f"[cloudflare-ddns] Failed to determine public IP: {e}", err=True
            )

        if once:
            break
        time.sleep(interval)


if __name__ == "__main__":
    main()
