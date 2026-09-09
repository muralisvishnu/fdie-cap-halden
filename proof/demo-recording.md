# Demo recording (asciinema)

Record a walkthrough of the Halden cage for the FDIE submission.

## Install asciinema

```bash
brew install asciinema
```

## Suggested script

```bash
asciinema rec proof/halden-cap-demo.cast

# Inside the recording:
make status
curl -fsS http://127.0.0.1:30080/login | head -1
make airgap-test
bash scripts/auth-login.sh demo@halden.local
# (submit email in browser, paste OTP from logs)
exit
```

## Upload

```bash
asciinema upload proof/halden-cap-demo.cast
```

Commit the `.cast` file or link in your README / submission.
