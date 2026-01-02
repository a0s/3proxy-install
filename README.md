# 3proxy-install

![Lint](https://github.com/a0s/3proxy-install/workflows/Lint/badge.svg)

**This project is a bash script that aims to setup a [3proxy](https://github.com/z3apa3a/3proxy) proxy server on a Linux server, as easily as possible!**

3proxy is a tiny free proxy server that supports HTTP, HTTPS, SOCKS4, and SOCKS5 protocols. This installer script helps you quickly set up a secure 3proxy server with user authentication.

Please check the [issues](https://github.com/a0s/3proxy-install/issues) for ongoing development, bugs and planned features!

## Requirements

Supported distributions:

- [x] Ubuntu >= 18.04
- [ ] AlmaLinux >= 8 (not tested yet)
- [ ] Alpine Linux (not tested yet)
- [ ] Arch Linux (not tested yet)
- [ ] CentOS Stream >= 8 (not tested yet)
- [ ] Debian >= 10 (not tested yet)
- [ ] Fedora >= 32 (not tested yet)
- [ ] Oracle Linux (not tested yet)
- [ ] Rocky Linux >= 8 (not tested yet)

## Usage

Download and execute the script. Answer the questions asked by the script and it will take care of the rest.

```bash
curl -O https://raw.githubusercontent.com/a0s/3proxy-install/master/3proxy-install.sh
chmod +x 3proxy-install.sh
./3proxy-install.sh
```

It will install 3proxy on the server, configure it, create a systemd service and set up user authentication.

Run the script again to add or remove users!

## Contributing

Contributions are welcome! Here's how you can help:

### Discuss changes

Please open an issue before submitting a PR if you want to discuss a change, especially if it's a big one.

### Code formatting

We use [shellcheck](https://github.com/koalaman/shellcheck) and [shfmt](https://github.com/mvdan/sh) to enforce bash styling guidelines and good practices. They are executed for each commit / PR with GitHub Actions, so you can check the [lint workflow configuration](https://github.com/a0s/3proxy-install/blob/master/.github/workflows/lint.yml).

## Credits & Licence

This project is under the [MIT Licence](https://raw.githubusercontent.com/a0s/3proxy-install/master/LICENSE)
