# Framework 16 Ryzen AI 300 speaker volume

On the tested Framework 16 (Ryzen AI 300, Realtek ALC285 subsystem `f111000d`), desktop volume turned down both channels of `Speaker` while leaving `Bass Speaker` at 0 dB. Their relative levels changed, making the sound thin at low volume.

The labels **appear swapped**: repeated isolated-tone recordings found `Speaker` supplied most of the low and mid-frequency output, while `Bass Speaker` was comparatively weighted toward treble. At 300 Hz, `Speaker` was 34–37 dB stronger; at 1 kHz, about 23 dB stronger. These built-in-microphone measurements establish acoustic contributions, not the identity of individual physical drivers.

## Fix

Enable software volume for the affected codec and set `Master`, `Speaker`, and `Bass Speaker` to 0 dB. Desktop volume then scales the complete output without changing its tonal balance. Both speaker controls receive the same setting, so swapping their names later will not affect the fix.

The installer and migration install a per-user WirePlumber rule and enable the startup service on first installation. Missing files are staged before publication, and the first enablement link is created before the complete unit is atomically published, so interrupted setup can finish on retry. Existing compatible files and symlinks stay in place while missing companions are installed; custom or unavailable configuration sources are preserved without installing a companion. Repeated setup preserves an existing service's disabled or masked state and leaves custom configuration files and user-managed symlinks alone, even when a symlink's current contents match the defaults. After WirePlumber starts, the initializer discovers the card, verifies software volume is active and all required controls exist, then sets their levels. Discovery timeouts retry after five seconds, subject to a systemd limit of four total starts within five minutes. Successful starts and manual or WirePlumber-triggered restarts also consume this allowance; it is a start-rate limit rather than a fresh discovery retry budget for each invocation. Once exhausted, automatic retries stop. A later requested start can run after the interval expires, or the counter can be cleared explicitly. Each attempt has a 30-second startup timeout; control failures and hung attempts remain failed without retrying. It preserves desktop volume and mute. Reboot applies the setup without interrupting playback during installation.

After correcting a persistent discovery or configuration failure, or when rapid audio-service restarts exhaust the start-rate limit, reset the failed service and start it again:

```bash
systemctl --user reset-failed omarchy-framework16-speaker-levels.service
systemctl --user start omarchy-framework16-speaker-levels.service
```

## Validation

Thirty-seven setup and initializer checks pass, including recovery from five interrupted installation stages, preservation of disabled and masked services, and recovery after discovery timeout. Eight symlink regression cases cover both setup and migration, mixer and unit links, enabled and disabled services, and continued visibility of external-source edits. Eight partial-configuration cases verify completion of a sole compatible symlink and safe preservation of custom or dangling sources without installing an unverified companion. Seven native WirePlumber checks load the shipped rule and verify matching and excluded devices using its configuration parser and matching engine; these checks require a C compiler and WirePlumber 0.5 development files and report a skip when unavailable. Four systemd policy checks use isolated transient services and fake audio commands to verify delayed recovery, stopping after four failed discovery attempts, no retry after control failure, and termination of hung discovery; they report a skip when no user manager is reachable. A temporary systemd service on the laptop also verified recovery after a simulated discovery timeout and successful initialization of the real hardware on retry.

Hardware checks confirm startup initialization, stable 0 dB speaker levels across desktop volume changes, and persistence across an Off-to-HiFi profile cycle, suspend/resume, and reboot. After suspend/resume and reboot, the software mixer remained active and `Master`, `Speaker`, and `Bass Speaker` were unmuted at 0 dB; desktop volume remained at 55% and unmuted. The startup initializer completed successfully after reboot.

[Upstream volume issue](https://github.com/NixOS/nixos-hardware/issues/1743) · [Framework discussion](https://community.frame.work/t/framework-16-speaker-volume-curve-issue/78591?page=2)
