# CI/CD Workflows

## Required GitHub Secrets

Add these in **Settings → Secrets and variables → Actions**:

### Android (Play Store)
| Secret | Description |
|-------|-------------|
| `PLAY_STORE_JSON_KEY` | Full contents of your Google Play service account JSON file |
| `KEYSTORE_BASE64` | Base64-encoded upload keystore (`base64 -i edanos-upload-keystore.jks`) |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_PASSWORD` | Key password |
| `KEY_ALIAS` | Key alias (e.g. `edanos-upload`) |

### iOS (TestFlight)
| Secret | Description |
|-------|-------------|
| `APP_STORE_KEY_ID` | Key ID from App Store Connect → Users and Access → Integrations → API |
| `APP_STORE_ISSUER_ID` | Issuer ID from the same page |
| `APP_STORE_KEY_P8` | Full contents of the downloaded `.p8` API key file |

**Note:** For iOS, you also need code signing set up (e.g. [fastlane Match](https://docs.fastlane.tools/actions/match/)) for the build to succeed on CI. The macOS runner does not have your local certificates.

## Triggers

- **Push to `main`**: Builds, runs tests, and deploys to Play Store (internal) / TestFlight
- **Pull requests**: Builds and runs tests only (no deploy)
- **Manual**: Use "Run workflow" in the Actions tab
