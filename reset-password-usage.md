# Reset a User Password

Use this when a server admin is locked out or needs to reset a DockEasy user's password. DockEasy does not have a UI or email reset flow for this yet.

## Steps

1. SSH into the VPS that runs DockEasy.
2. Confirm the API container is running:
   ```bash
   docker ps
   ```
3. Run the reset command with the user's email:
   ```bash
   docker exec -it dockeasy-api dotnet DockEasy.Api.dll reset-password admin@example.com
   ```
4. Copy the printed password, log in with it, then change it from **Settings -> Profile**.

All existing sessions for that user are signed out when the password is reset.

## Reset Authenticator App 2FA

Use this when a user cannot access their authenticator app or recovery codes.

```bash
docker exec -it dockeasy-api dotnet DockEasy.Api.dll reset-2fa admin@example.com
```

This disables two-factor authentication, resets the authenticator key, and signs out all existing sessions for that user. The user can log in with their password and configure 2FA again from **Settings -> Profile**.
