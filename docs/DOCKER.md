# Permanent local hosting

The web app can run as a small, restartable container on any always-on Docker
host. The container listens on TCP port `8765`, talks to the matrix over the
LAN, and serves the PWA to phones, tablets, computers, and native Apple apps.

The image is intentionally stateless. Matrix credentials are supplied as
environment variables, so no credential file needs to be committed or mounted.
The `restart: unless-stopped` policy brings the app back after a host reboot or
Docker restart. Use a fixed IP address or DHCP reservation for the matrix and
set `MATRIX_HOST` to that address; this avoids container DNS/mDNS differences
between Docker hosts.

## Fast path on the Docker host

From the repository root:

```sh
cp .env.example .env
# Edit .env, especially MATRIX_HOST and MATRIX_PASSWORD.
docker compose up -d --build
docker compose ps
curl http://127.0.0.1:8765/healthz
```

Open `http://<docker-host-ip>:8765` from another device on the same network.
The container does not need privileged access, host networking, or a volume.

## Portainer management

Portainer can manage the container as a Stack. There are two supported paths:

### Same host as the Docker CLI

1. Build the image on the Docker host: `docker build -t hdmi-matrix-ui:local .`.
2. In Portainer, select the Docker environment, then **Stacks → Add stack**.
3. Name it `hdmi-matrix`.
4. Paste [`deploy/portainer/stack.yml`](../deploy/portainer/stack.yml) into the
   web editor.
5. Add stack environment variables for `MATRIX_HOST`, `MATRIX_USERNAME`,
   `MATRIX_PASSWORD`, and optionally `HDMI_MATRIX_PORT`.
6. Deploy the stack. The service should show `healthy` after startup.

The `hdmi-matrix-ui:local` image must exist on the Docker host used by
Portainer. If Portainer manages a different host, build and push the image to a
registry that host can reach, then set `HDMI_MATRIX_IMAGE` to the full image
name and tag in the stack environment variables.

### Deploying from a Git repository

Portainer's Git stack workflow is useful when the repository is available to the
Portainer host. Set the compose path to `deploy/portainer/stack.yml`, use a
registry-backed `HDMI_MATRIX_IMAGE`, and keep secrets in Portainer's stack
environment-variable editor rather than in Git.

### Routine operations

```sh
docker compose pull                 # registry image deployments
docker compose up -d                # apply environment or stack changes
docker compose logs -f hdmi-matrix  # inspect startup and matrix errors
docker compose restart hdmi-matrix
docker compose stop                 # stop without removing the container
docker compose down                 # remove the container (image is kept)
```

In Portainer, the same operations are available from the Stack page. Use
**Logs** for connection failures, **Inspect** to confirm the published port and
environment, and **Recreate** after changing an environment variable. A healthy
container only means the web service is running; `/api/state` still depends on
the matrix being reachable.

## CasaOS and ZimaOS

CasaOS and ZimaOS both accept a Docker Compose application template. Import
[`deploy/casaos/compose.yaml`](../deploy/casaos/compose.yaml), then set the
matrix host, credentials, and published port in the app's environment settings.
The template includes `x-casaos` metadata, amd64/arm64 architecture hints, a
health check, a safe restart policy, and the app icon/landing path.

If the host cannot pull a registry image, build the image on that host first:

```sh
docker build -t hdmi-matrix-ui:local .
```

Then import the template with `HDMI_MATRIX_IMAGE=hdmi-matrix-ui:local`. If the
CasaOS/ZimaOS UI only accepts a registry image, push the same Dockerfile output
to a registry and set `HDMI_MATRIX_IMAGE` to that immutable tag.

## Network and security notes

- Keep port `8765` on the trusted home LAN. The app is a local control proxy,
  not an internet-facing authentication boundary.
- Do not port-forward `8765` to the internet.
- The matrix itself is contacted over plain HTTP because that is the device
  protocol. Use a private LAN/VLAN and a fixed matrix IP.
- The included health check intentionally does not contact the matrix. This
  keeps Docker/Portainer/CasaOS status useful while the hardware is powered
  off; diagnose hardware reachability with the app status indicator and logs.
- If the matrix hostname does not resolve inside Docker, use its IP address in
  `MATRIX_HOST` instead of adding a host-network dependency.
