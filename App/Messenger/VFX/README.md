# VFX previews and messenger integrations

Copied from the local `demo/controller/controller` working tree on 2026-10-25.
The existing Contact MetalVFXEngine views and shaders are reused. New particle
engine/chart code lives in `App/MetalVFXEngine/ParticleMorph` and `ParticleCharts`;
its shared C/Metal structures are exported to Swift through `:ParticleTypes`.

## Settings → VFX

- Matrix + Kinetic Login: a separate registration visual prototype.
- Photo Feed: the original carousel and blue liquid page dots.
- Voice Room: the original group-call layout and simulated speakers.
- Bubble Cluster: the original linked avatars and broadcast UI prototype.
- Particle Morph: Pay, AI, VIP and Load; Tabs and Snap are not presented.
- Particle Charts: the complete Storage, Bars, Line and Morph examples.
- Photo Viewer, Translate Post, Community Notes and Post Analytics preserve the
  original X visual examples as standalone screens.
- Vanish Mode preserves the original gesture/transition example.
- Liquid Toast + Quick Reply uses the existing toast and inline composer.
- Chat Playground opens a local-only messenger conversation with a three-photo
  stack. Tap once to spread it, then a photo to open the viewer. Its Call button
  exposes Vanish Mode, a sample incoming notification and the wallpaper picker.

## Messenger

Hold Send with non-empty text to choose a message effect. Empty-field holding
still records voice/video. The selected effect is optional message metadata;
existing stored payloads decode without it. The playground and messages composed
in Vanish Mode stay in the controller's memory and disappear when the chat closes.
Pull up past the bottom of a personal/group chat to toggle Vanish Mode.

The chat theme picker includes Fluid Mesh. Group chat Call opens the Voice Room
prototype. Public demo channel Call opens Bubble Cluster. The standard photo
viewer retains its paging/zoom and uses the X example's opening spring settings.
Paper Burn is a replayable visual preview on selected chat bubbles and public
channel posts; its completion restores the original view.

Public/private membership and administrator rights are explicit prototype
fixtures: channel IDs 3, 9 and 16 are public; ID 17 is not. The first account is
the demo administrator of VFX Daily (ID 3). Long-pressing a public post retains
the liquid reaction picker and adds translation, context, Paper Burn and, for
that administrator, analytics. Guards also apply at action execution. The first
post of each public example has a collapsible community-context block. Context,
translation and analytics are labelled demonstration data; no translation or
analytics service is called.

Quick Reply can also respond through the normal send path when an observed
incoming history update produces a toast. The catalog's sample notification and
the playground require no fabricated backend deliveries or recurring timers.
