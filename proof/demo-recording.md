# Demo recording (uncut install)

The brief asks for **one install from zero, uncut**. Commit `proof/halden-cap-demo.cast`.

```bash
brew install asciinema
export TARGET=cage
make record-install
# inside the recording:
make down TARGET=cage
make up TARGET=cage
make mirror TARGET=cage
make install-addons TARGET=cage
ALLOW_NON_THURSDAY=1 make install-ingress TARGET=cage
make capture-denials TARGET=cage
make airgap-test TARGET=cage
make test-smoke TARGET=cage
exit
git add proof/halden-cap-demo.cast && git commit -m "Add uncut kind install recording"
```

Do not edit the cast. Kind only — GKE Hub path is a separate lab (ADR-010).
