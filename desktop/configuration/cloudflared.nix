{
  config,
  ...
}:
{
  # Built as the Hermes Telegram gateway's public webhook endpoint; the
  # gateway is retired (the bot is now the Qwen Code channel in
  # home/agents.nix, which long-polls and needs no inbound route), but the
  # tunnel is kept per operator request. tg.codebam.ca still forwards to
  # 127.0.0.1:8443, where nothing listens until a new consumer claims it.
  # cloudflared holds an outbound-only tunnel, so nothing listens on the WAN.
  # The tunnel is locally managed -- credentials from SOPS, ingress declared
  # here -- so route changes ship with the repo instead of the Cloudflare
  # dashboard. `default` is the required catch-all for names that match no
  # ingress rule.
  services.cloudflared = {
    enable = true;
    tunnels.hermes-telegram = {
      credentialsFile = config.sops.secrets.cloudflared-tunnel-credentials.path;
      ingress."tg.codebam.ca" = "http://127.0.0.1:8443";
      default = "http_status:404";
    };
  };
}
