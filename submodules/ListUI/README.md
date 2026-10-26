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

Row heights and list geometry use synchronous manual frames. `AsyncListItem`
prepares text measurements and unloaded Texture nodes on a shared worker queue
limited to two concurrent tasks. Its returned closure applies the result on the
main thread. A changed version, width, theme, or recycled identity cancels the
previous preparation; completion also checks operation and node identity before
applying. Ordinary `ListItem` consumers keep their synchronous update path.
Chat rows use this asynchronous path and layer-backed text/icon nodes. Gesture
dependencies are configured on row updates rather than every scrolling frame.
This is not Telegram's full list engine: variable-height background geometry,
long-history anchoring and chat-specific grouping remain separate work.

`ListItemNode.updateViewport` reports actual row visibility separately from
preloading. Media is suspended during dragging, deceleration, and programmatic
scrolling, then resumes after the scroll settles. Owners set
`ListView.mediaPlaybackEnabled` to disable playback in covered screens or inactive
pages. A retained but offscreen row must release its media resources.

Contact's consumers are `App/Messenger/ChatList` and `App/Messenger/Profile`.
The profile composes an app-owned photo/header, a pinchable media grid and
attachment lists. The original standalone Settings demo has been removed.

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
pass through the shared driver. While the common header is collapsed, returning
to a pane preserves its offset. Revealing the header resets every pane to the
top, including saved offsets of evicted pages, so switching tabs cannot restore
old content underneath an expanded profile.

`CollapsingListContainerNode.pinnedTopInset` reserves room for the app's
overlaid navigation bar. Updating its header height with
`preservingContentPosition: true` supports an animated expanding profile photo
without interrupting the shared motion. `ListPagerNode.setTabsNode(_:height:)`
lets an app keep its own selector in the pinned tab area.

## Existing UIKit rows and application chrome

`ListItemNode` exposes interaction and selection-failure gesture hooks so an
existing UIKit row can keep its controls and long press while being virtualized
by ListUI. `closeInteractions` and `blocksHorizontalPaging` integrate custom row
controls with selection and scrolling. `ListView.itemNode(for:)` locates a loaded
row by its stable identity for previews and app-owned effects.

`ListView.contentInsets`, scrolling callbacks and the proposed target-offset
callback let an app keep an existing navigation/story header. `ListPane` exposes
normalized offsets (zero means the top including insets). `ListPagerNode` can
hide its built-in tabs, report page progress, accept external page selection and
use full-width horizontal paging. By default, paging uses the center/edge
gesture policy described above. Contact's chat controller uses these hooks to
preserve its existing navigation and row design.
