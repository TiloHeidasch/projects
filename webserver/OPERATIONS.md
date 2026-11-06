# Webserver operations

`WEB_ROOT_PATH` must already exist on the host before the stack starts. Place
the site contents, such as `index.html`, there locally; these files are never
checked into Git.

Configure the Cloudflare Public Hostname Origin as `http://nginx:80`. Put the
Tunnel token only in the ignored `.env` as `TUNNEL_TOKEN`; never commit it.

The webserver has no host port and is reachable exclusively through the
Cloudflare Tunnel.
