# Debug Workflow
1. Check crash logs and stack traces
2. Verify sandbox entitlements in .entitlements file
3. Look for race conditions in async code
4. Check thread-safety (especially inet_ntoa, shared state)
5. Test mode transitions if UI-related
6. Build and run to verify fix
