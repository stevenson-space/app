# MCP Servers

## Figma MCP server rules

Figma is used only to design App Store screenshots. Do not use it to generate or change app UI code, and do not translate Figma designs into SwiftUI.

- Load the `figma-use` skill before calling `use_figma`. It ships with the Figma plugin; without the plugin, read the Figma MCP server's `skill://figma/figma-use/SKILL.md` resource instead.
- Use real screenshots captured from the iOS Simulator as the app imagery; don't redraw or mock up the app UI.
- Upload those screenshots with `upload_assets` rather than recreating them.
- Don't add placeholder imagery or new icon packages; take any icons and assets from the Figma file.
- Size frames to App Store Connect's required screenshot dimensions. For resizing and validating exported screenshots, use the `asc-screenshot-resize` skill. It isn't checked in; install it with `asc install-skills` or `npx skills add rorkai/app-store-connect-cli-skills`.
- Check the result with `get_screenshot` before calling a design done.
