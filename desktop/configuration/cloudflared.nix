{
  config,
  ...
}:
{
  # Originally the Hermes Telegram gateway's public webhook endpoint. Retired
  # with that gateway, then reclaimed for the Matrix appservice webhook bridge:
  # matrix-workers pushes appservice transactions to https://tg.codebam.ca,
  # which cloudflared forwards to the local bridge on 127.0.0.1:3081.
  # cloudflared holds an outbound-only tunnel, so nothing listens on the WAN.
  # The tunnel is locally managed -- credentials from SOPS, ingress declared
  # here -- so route changes ship with the repo instead of the Cloudflare
  # dashboard. `default` is the required catch-all for names that match no
  # ingress rule.
  services.cloudflared = {
    enable = true;
    tunnels.hermes-telegram = {
      credentialsFile = config.sops.secrets.cloudflared-tunnel-credentials.path;
      ingress."tg.codebam.ca" = "http://127.0.0.1:3081";
      default = "http_status:404";
    };
  };
}
