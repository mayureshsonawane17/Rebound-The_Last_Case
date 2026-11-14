# Editing BounceFlux in Godot

Open `project.godot` with Godot 4.7.2 (the version used for validation). Open a scene in `scenes/levels/` and select the **2D** workspace. All five layouts are stored in their scene files; no level geometry is generated at runtime.

## Move, resize and recolor platforms

Expand **World** in the Scene tree. Select a named floor, ledge, roof or crane and drag it, or change **Transform > Position**. The level uses reusable scenes from `scenes/world/`.

Expand that instance and select **Collider**. Edit **Shape > Size** or use the rectangle handles. Each platform has its own shape. If a child is hidden, right-click the instance and enable **Editable Children**. Use **Make Unique** before sharing/duplicating a shape you plan to resize independently. Keep collider and Visual centered together; resize the shape rather than scaling the whole physics body. The visual follows the rectangle size automatically.

Select **Visual** to change **Base Color**, **Edge Color**, or optional **Texture**. A texture replaces the placeholder and fits the collider's rectangle; adjusting colors never changes collisions. The warehouse and headquarters **ReleaseCatwalk** instances are solid from every side. Other thin ledges retain **One Way Collision**; floors and walls are solid.

Crane instances expose **Amplitude** (horizontal/vertical travel) and **Angular Speed**. Their scene position is the motion center. Vertical motion starts at center + vertical amplitude when played; the editor shows the center. Rewind restores their phase and position.

## Player movement and sprites

Select **Player** in a level, or open `scenes/player.tscn` to change defaults for all levels. Under **Movement**, edit **Move Speed**, **Acceleration**, **Gravity** and **Jump Speed**. Defaults are 330, 1800, 1500 and -720. More negative jump speed means a higher jump. Jump forgiveness/buffering remain 0.10 seconds in `scripts/player.gd`.

Assign the optional **Texture** to replace the drawn ball. Its collider remains separate. Evidence, guards and traps also expose optional Texture properties; no image is required. Store replacement PNGs under `assets/characters/`, `assets/props/` or `assets/backgrounds/` as appropriate.

## Enemies, hazards and evidence

Select **Guard** or **BossGuard**, change **Position**, then adjust **Patrol Distance**, **Speed**, and **Is Boss**. Patrol distance is measured on either side of the starting x position.

Select a trap to move it or change **Trap Type**, **Fall Speed** or **Cycle Time**. Keep falling crates in an unobstructed shaft above the patrol area. **Trigger Delay** controls the crate warning. **Reset Delay** controls the pause after impact; the same box rearms when its original position is clear. Electric cycles spend 25% charging, 35% discharging and 40% cooling down; only the outlined discharge area is dangerous.

Select **World > TrapRelease** to move the visible amber RELEASE marker/area. Its **Trap Path** must point to the intended crate (currently `../../CrateTrap` or `../../BossCrateTrap`). Its Collider matches the visible yellow 40×8 marker. Touch it with the ball or click inside that rectangle; the label and space around it are not clickable. No new controller code is needed to reconnect it.

Select **Evidence** and move it. Keep **Evidence Id** consistent with the level root's **Evidence Id** (`evidence_1` through `evidence_5`). Keep it above a reachable platform. Select **ExitDoor** to move the exit. Leave the root child names Player, Evidence and ExitDoor unchanged because the controller looks them up.

## Background layers

Select the separate **Background** node. Change **Background Color**, **Near Color**, **Far Color**, or its optional **Texture**. Its drawing is behind gameplay at z-index -10 and has no collision. Additional Sprite2D or Polygon2D children can be placed under Background for independent decorative layers. Set decorative z-indices below gameplay and keep all platform/interactive nodes outside Background.

## After an edit

Save the scene, press **F6** to test that level, or **F5** for the full game. Controls: A/D or arrows, Space jump, R rewind, Escape pause. Check jumps, evidence pickup, exit and rewind after moving any gameplay object. Keep both Macs on the same Godot version and avoid simultaneous edits to the same `.tscn`.

Automated route tests encode the current layout, so intentional layout changes may require updating `tests/level_routes.gd`. See `docs/INTEGRATION_STATUS.md` for commands and actual validation results.
