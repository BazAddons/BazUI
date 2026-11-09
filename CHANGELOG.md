## 027

- Added built-in developer error reporting to BazUI's core. No separate error-catching addon is required.
- Use **`/baz errors`** to browse runtime Lua errors, startup failures and blocked-action reports, then select and copy a report for troubleshooting. Previous/Next, Copy all and Clear controls are included.
- Repeated errors are grouped and counted. The newest 50 reports are saved across reloads in a separate developer log, with flood protection and throttled notifications. Existing BugGrabber installations are supported.
- Fixed aura timers overflowing into adjacent icons. Timers now stay on one line inside each icon, and font sizes are capped to fit.
- Live aura containers now respect each row's timer visibility and font settings, matching the preview. Layout changes wait until combat ends.
