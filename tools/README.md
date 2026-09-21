# Feather remote CLI

Drive Feather on the device from a computer: import, sign, install, export, certificates, sources.

## Turn it on

Feather → Settings → Features → **Remote CLI** → enable. The screen shows the address to reach it at,
and the computers that are currently paired.

Feather has to stay open on the device — iOS suspends the server when the app goes to the background.

## Pair

Over USB (no shared network needed, wants `iproxy` from `libusbmuxd-utils`):

```sh
feather login --usb
```

That starts the tunnel itself and leaves it running, and every later command brings it back up if it
died. Over Wi-Fi, pass the address shown in Settings instead:

```sh
feather login http://192.168.1.5:8420
```

Either way the computer prints a code and waits:

```
Pairing code: 481920
Allow the request on the device, then type that code there.
```

The device asks whether to allow that computer, naming it and its address, and then asks for the
code. Type the printed one. Only then does the device hand out a token, which lands in
`~/.config/feather-cli.json` (mode 600). The code is hashed before it is sent, so it never travels
over the wire.

Swiping a row away under **Paired Computers** cuts that computer off immediately.

`FEATHER_HOST` / `FEATHER_TOKEN` override the stored file, which is handy for scripts and a good way
to confuse yourself otherwise — `feather status` prints the host it is using.

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

JSON over HTTP, everything under `/v1`. Every route needs `Authorization: Bearer <token>` except
`/v1/pair`, which is how a computer gets one. Errors come back as
`{"error": true, "reason": "..."}` with a normal HTTP status.

`/v1/pair` holds the request open until the person with the device allows it and types the code
(2 minute limit), so expect it to sit there. One pairing can be in flight at a time.

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/v1/pair` | `{name, codeHash}` | `{token, device}` once allowed on the device |
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

A paired token is all a computer needs to use your certificates, so keep the toggle off when you are
not using it, and unpair anything you do not recognise.
