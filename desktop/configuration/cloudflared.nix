{
  config,
  ...
}:
{
  # The Hermes Telegram gateway's public webhook endpoint. cloudflared holds
  # an outbound-only tunnel, so nothing listens on the WAN: tg.codebam.ca
  # resolves to Cloudflare and forwards to the gateway's loopback listener
  # (TELEGRAM_WEBHOOK_* in home/hermes.nix). The tunnel is locally managed --
  # credentials from SOPS, ingress declared here -- so route changes ship
  # with the repo instead of the Cloudflare dashboard. `default` is the
  # required catch-all for names that match no ingress rule.
  services.cloudflared = {
    enable = true;
    tunnels.hermes-telegram = {
      credentialsFile = config.sops.secrets.cloudflared-tunnel-credentials.path;
      ingress."tg.codebam.ca" = "http://127.0.0.1:8443";
      default = "http_status:404";
    };
  };
}
