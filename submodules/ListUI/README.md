# ListUI

`//submodules/ListUI` is Contact's app-independent list UI module, built on UIKit
and the vendored AsyncDisplayKit Core.

## Layers

- `List`: stable item identities, change sets, virtualized vertical scrolling,
  and reusable `ASDisplayNode` rows. There is no UITableView or ASTableNode.
- `ItemList`: the controller, state and sections. One page works without tabs;
  multiple pages enable the horizontal pager.
- `Container`: an app-supplied collapsing header, pinned tabs and a single vertical
  gesture/inertia driver shared with the active pane.
- `Panes`: the `ScrollablePane` contract and the `ListPane` adapter. Custom grids
  and components can be supplied through `ListPage(makePane:updatePane:)`.
- `Paging`: interactive page movement, the tab indicator and per-page offsets.
  Only the current page and its neighbors are retained; other offsets are saved.
- `Reveal`: independent leading/trailing row actions, partial reveal, full swipe
  for non-destructive trailing-in-strip actions, and accessibility actions.
  Destructive actions require tapping their button.
- `Gestures`: the shared ownership policy prevents paging and row reveal from
  consuming the same drag.
- `Presentation`: caller-provided colors and reduced-motion-aware transitions.

With multiple pages, center horizontal drags page between lists and edge drags
reveal row actions (edge width: one-sixth of the viewport, clamped to 22–80 pt).
Without tabs, horizontal row drags reveal actions anywhere. Vertical movement
scrolls in either mode. Open row actions block paging until closed. Tapping the
row body closes actions, and dragging vertically closes them too.

Apps implement immutable `ListItem` descriptors. IDs must be unique within a
page; the same chat may appear on several pages. Increment `version` when row
content or actions change. The descriptor creates a reusable `ListItemNode`
and applies app-specific content; use `RevealableItemNode` for swipe actions.
The app owns handlers and mutations. Pass a new `ItemListState` to apply them;
no full table reload is involved. A visible anchor is preserved across changes.

This initial implementation uses synchronous row-height measurement and manual
frames; ASTextNode renders text through AsyncDisplayKit. It is not Telegram's
full asynchronous measurement pipeline or a chat-history engine. Long-history
anchoring, media preloading and chat-specific grouping are future extensions.

`App/Messenger/ListDemo` is a consumer example with independent in-memory data.
Open Settings → List Demo. Its Tags button adds/removes three folder pages;
Plus inserts a row, and the update icon modifies a row on the selected page.

## Collapsing header and component composition

Call `ItemListController.setScrollingHeader(_:height:)` with an app-owned
`ASDisplayNode`. The header can contain arbitrary text, images and controls.
`CollapsingListContainerNode` moves the header out first and then drives the
active pane's vertical offset. On the way back, the pane reaches its top before
the header expands. The pager's tabs pin below the controller's toolbar.

One ancestor vertical recognizer and one display-link inertia integrator own the
motion across both regions. The internal list's native vertical scrolling is
disabled from its first layout in this mode; it stays native when used alone.
Horizontal paging and row reveal retain their direction policy. Velocity is not
reset when crossing the header boundary. Edge elasticity is applied by the same
coordinator, and motion stops when the screen leaves or the app resigns active.

`ScrollablePane` exposes its node, vertical offset and maximum offset, geometry
updates, external scroll requests and interaction cancellation. `ListPane`
adapts `ListView`. A grid can supply another adapter without importing any
profile or chat data into ListUI. Accessibility up/down scrolling requests also
pass through the shared driver. Returning to a previously scrolled pane keeps its
offset and collapses the common header so that its content remains coherent.

The demo's `DemoProfileHeaderNode` provides an avatar, bio and three independent
buttons. The Tags toggle works both with and without the collapsing header; no
extra tap is needed to initialize the vertical scroll driver.
