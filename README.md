# Spacelift (Ansible) 💖 Tailscale

Puts [Tailscale][] into [Spacelift][], for accessing things on the tailnet from Ansible, etc easily.

[Tailscale]: https://tailscale.com/
[Spacelift]: https://spacelift.io/

The original commands defined in your Spacelift workflow are still invoked by Spacelift, we just wrap some setup/teardown around them for Tailscale.

This is a fork of [caius/spacelift-tailscale](https://github.com/caius/spacelift-tailscale) with the Dockerfile modified to use Spacelift's [runner-ansible image](https://github.com/spacelift-io/runner-ansible) instead of Spacelift's [runner-terraform image](https://github.com/spacelift-io/runner-terraform). 

The Dockerfile has also been modified to layer on a handful of extra packages in addition to `tailscale` to make the integration with Tailscale work out of the box.

Additional packages:

- `bash` (for the `spacetail` script)
- `netcat-openbsd` (for Ansible's SSH connection type)

See Howee Dunnit below for implementation details (extra important for Ansible SSH connections!).

## Usage

There is some up front configuration required, then it'll Just Work™ every time you trigger a run in Spacelift for that stack.

There's three things that need configuring, the `runner_image` for the stack, some before/after phase hooks and the `TS_AUTH_KEY` for authenticating to the Tailnet.

Spacelift has multiple ways of configuring these settings, see [Configuration][] documentation for more info. Below is a suggested way to configure it, but not essential.

[Configuration]: https://docs.spacelift.io/concepts/configuration/

Caius' original Terraform repo states the following:

> This mechanism relies on Terraform providers using HTTP libraries that pay attention to the `http_proxy` environment variable for using a HTTP Proxy to communicate via. The default `net/http` library in Golang's stdlib does pay attention to this, so providers like `hashicorp/nomad` Just Work™ by pointing at the tailscale MagicDNS hostname of a nomad server.

> (If you're using Tailscale Serve to expose the endpoint the Terraform provider needs the full MagicDNS hostname, including the Tailscale domain.)

However, if you're using Ansible to connect over Tailscale to a host via SSH, you'll need to set a ProxyCommand in your Ansible inventory file to use the SOCKS5 proxy. The Dockerfile has been modified to install `netcat-openbsd` to make this possible, as the default BusyBox `nc` does not support the `-x` flag. For example, in your inventory file you could set:

```yaml
my-tailnet-stack:
  hosts:
    my-host: <tailnet-ip-address>
  vars
    ansible_connection: ssh
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o ProxyCommand="nc -X 5 -x localhost:1080 %h %p"'
```

### Context for hooks & auth

If you manage Spacelift via Terraform, lean on [caius/terraform-spacelift-tailscale](https://registry.terraform.io/modules/caius/tailscale/spacelift/latest) module to setup a context for you for the hooks. You can also specify an `autoattach:` label on the Context to be able to easily associate it with Stacks.

Otherwise you'll need to create a Spacelift Context in the UI and define the following hooks for the before phases (plan/perform/apply/destroy) (apply and destroy do not apply to Ansible):

- `spacetail up`
- `trap 'spacetail down' EXIT`
- `export HTTP_PROXY=http://127.0.0.1:8080 HTTPS_PROXY=http://127.0.0.1:8080`

And then in the after hooks for all the above phases, the following:

- `unset HTTP_PROXY HTTPS_PROXY`
- `sed -e '/HTTP_PROXY=/d' -e /HTTPS_PROXY/d -i /mnt/workspace/.env_hooks_after` (Due to https://github.com/caius/spacelift-tailscale/issues/14)

The `TS_AUTH_KEY` environment variable below can be ClickOps'd into this context as well.

### Runner Image

The `runner_image` needs configuring through either `.spacelift/config.yml` or the Spacelift Stack Settings UI.

Firstly the `runner_image` needs setting to `ghcr.io/nathanwasson/spacelift-tailscale-ansible:latest` (or pin a specific SHA[^1] instead of `latest` to control updates.)

[^1]: <https://github.com/nathanwasson/spacelift-tailscale-ansible/pkgs/container/spacelift-tailscale-ansible/versions?filters%5Bversion_type%5D=tagged> lists all available SHA tags for the image.

```yaml
stacks:
  my-tailnet-stack:
    runner_image: "ghcr.io/nathanwasson/spacelift-tailscale-ansible:latest"
```

### Tailnet Authentication

Configuration is via various envariables in the Spacelift runner container, "inspired"[^2] by tailscale's `containerboot` binary.

[^2]: copied from. Build on the shoulders of giants, and be consistent.

Required configuration:

- `TS_AUTH_KEY` - Tailscale auth key (Suggest creating ephemeral & tagged key)

Optional configuration:

- `TS_EXTRA_ARGS` - Extra arguments to pass to `tailscale up`. eg, `--ssh` for debugging inside the spacelift container
- `TS_TAILSCALED_EXTRA_ARGS` - Extra arguments to pass to `tailscaled`. eg, `--socks5-server=localhost:1081` to change socks5 port
- `TRACE` - set to non-empty (eg, "1") to debug `spacetail` script

As above we suggest setting these directly on the Context so any Stack you attach the Context to will be able to access the Tailnet.

## Howee Dunnit

Spacelift runs terraform (or other tooling) in containers, and overrides the initial command run in each container. The `/mnt/workspace` directory is mounted into each container and the environment variables are the same as the phases run.

Tailscale needs `tailscaled` running, which we can start in a `before_` phase hook in Spacelift. The tricky bit is we need to stop it before the phase ends, otherwise Spacelift will wait for the phase to time out in the case of the terraform command erroring, and also won't call any of the `after_` phase hooks. (This is due to how Spacelift executes everything, usually this is what you want!)

To work around this, we use a shell `trap` in the `before_` phase hooks to define a command to execute when the shell exits. We use this to stop tailscaled regardless of whether the terraform command errored or not. This means the container exits fairly quickly on completion and Spacelift can deal with the success or failure therein.

Due to running tailscaled with userspace networking, we don't get MagicDNS wiring up requests for us. Packets are routed to the correct IPs without us having to do anything however, so we just need to solve the DNS issue.

The suggested solution from Tailscale documentation is to use either a SOCKS5 or HTTP Proxy. We run http proxy on `localhost:8080` and socks5 on `localhost:1080` in the container by default, so that's likely the easiest way to go. This requires the running process to be able to use either proxy to make connections via. Anything using Go's `net/http` library should be able to use it automatically, which includes Terraform Providers hitting HTTP APIs.

## License

See [LICENSE](./LICENSE) file.
