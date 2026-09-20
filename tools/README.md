# Feather remote CLI

Drive Feather on the device from a computer: import, sign, install, export, certificates, sources.

## Turn it on

Feather → Settings → Features → **Remote CLI** → enable. The screen shows the address, the token,
and a *Copy Connection Command* button that puts this on the clipboard:

```sh
export FEATHER_HOST=http://192.168.1.42:8420
export FEATHER_TOKEN=<token>
```

Feather has to stay open on the device — iOS suspends the server when the app goes to the background.

## Connect

Wi-Fi: use the address shown in Settings.

USB (works without a shared network, needs `libimobiledevice`):

```sh
iproxy 8420 8420 &
feather login http://127.0.0.1:8420 <token>
```

`feather login` stores the host and token in `~/.config/feather-cli.json`; `FEATHER_HOST` /
`FEATHER_TOKEN` override it.

## Use

```sh
feather status
feather apps
feather import MyApp.ipa --sign --install     # one shot: upload, sign, install
feather import https://host/MyApp.ipa --sign --install   # a url works too, fetched here then uploaded
feather sign MyApp --cert 0 --bundle-id com.me.app
feather install MyApp
feather export MyApp -o signed.ipa
feather rm MyApp
feather certs
feather cert-add cert.p12 cert.mobileprovision --password hunter2 --default
feather sources
feather source-add https://example.com/repo.json
```

An app is named by uuid, uuid prefix, or part of its name.

Transfers show a bar, signing and packaging show elapsed time (the device reports no percentage for
those), and installs show installd's own progress, polled from `/v1/apps/{uuid}/progress`. All of it
goes to stderr, so `feather apps | grep ...` stays clean.

`install` hands the app to Feather's own install sheet, so it obeys whichever installation method is
set in Settings (server or idevice) and needs Feather to be in the foreground.

## Protocol

JSON over HTTP, one bearer token, everything under `/v1`. Errors come back as
`{"error": true, "reason": "..."}` with a normal HTTP status.

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/v1/status` | | app, device, installation method, protocol version |
| GET | `/v1/apps` | | `{apps: [...]}` |
| POST | `/v1/apps?filename=x.ipa` | raw ipa bytes | the imported app |
| DELETE | `/v1/apps/{uuid}` | | `{ok: true}` |
| GET | `/v1/apps/{uuid}/ipa` | | the packaged ipa |
| POST | `/v1/apps/{uuid}/sign` | `{certificate, name, identifier, version, install}` | the signed app |
| POST | `/v1/apps/{uuid}/install` | | `{ok: true}` |
| GET | `/v1/apps/{uuid}/progress` | | `{identifier, progress}` while installd works |
| GET | `/v1/certificates` | | `{certificates: [...], selected: n}` |
| POST | `/v1/certificates` | `{p12, provision, password, name, makeDefault}` (base64) | the certificate list |
| GET | `/v1/sources` | | `{sources: [...]}` |
| POST | `/v1/sources` | `{url}` | `{ok: true}` |

So `curl` works too:

```sh
curl -H "Authorization: Bearer $FEATHER_TOKEN" $FEATHER_HOST/v1/apps
```

The token is the only thing standing between your certificates and the rest of the network. Keep the
toggle off when you are not using it, and regenerate the token if it leaks.
