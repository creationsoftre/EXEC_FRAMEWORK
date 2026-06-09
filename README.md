# exec_framework

Core EXEC framework for FiveM servers with arena sessions, loadouts, add-on weapons, gangs, leaderboards, passive zones, respawn handling, and Tebex weapon unlocks.

## Dependencies

- `ox_lib`
- `oxmysql`
- MySQL database
- Optional: `exec_multichar`
- Optional: `exec_killfeed`

## Installation

1. Put `exec_framework` in your server `resources` folder.
2. Import `database/exec_framework.sql` into your MySQL database.
3. Start dependencies before this resource.
4. Add the resource to `server.cfg`.

```cfg
ensure ox_lib
ensure oxmysql
ensure exec_framework
```

Full EXEC stack example:

```cfg
ensure ox_lib
ensure oxmysql
ensure fivem-appearance
ensure exec_hud
ensure exec_multichar
ensure exec_framework
ensure exec_killfeed
```

## Main Configs

- `config/gameplay.lua`
- `config/arenas.lua`
- `config/weapons.lua`
- `config/addon_weapons.lua`
- `config/attachments.lua`
- `config/gangs.lua`
- `config/leaderboard.lua`
- `config/integrations.lua`

## Integration Bridges

EXEC uses bridge files so CAPO can swap common server resources without editing arena, gang, respawn, or loadout logic directly.

Bridge files live in `bridge/`:

- `bridge/appearance.lua`: appearance menu open/save flow
- `bridge/hud.lua`: external HUD hide/show calls
- `bridge/identity.lua`: citizen ID, license, and multichar selector hand-off
- `bridge/inventory.lua`: weapon giving, ammo, vitals, and weapon clearing
- `bridge/killfeed.lua`: kill payload routing
- `bridge/notify.lua`: client/server notification routing
- `bridge/spawn.lua`: spawnmanager auto-spawn and safe respawn placement
- `bridge/target.lua`: future entity/zone interaction targets
- `bridge/voice.lua`: normalized talking state checks

Most server owners only need to edit `config/integrations.lua`.

Default providers:

```lua
hud        = 'exec_hud'
appearance = 'fivem-appearance'
identity   = 'exec_multichar'
inventory  = 'native'
killfeed   = 'exec_killfeed'
notify     = 'ox_lib'
spawn      = 'spawnmanager'
target     = 'none'
voice      = 'native'
```

Set a provider to `'none'` to disable that integration. Custom event/export targets can be added in `config/integrations.lua` without changing framework gameplay files.

## Commands

- `/exec_menu`
- `/exec_hubhelp`
- `/exec_invite [server id]`
- `/exec_leader`
- `/exec_score`
- `/gangadmin`
- `/gangmenu`
- `/exec_weaponlock <license|playerId> <weapon> <lock|unlock>`

## Add-On Weapons

Add custom weapons in `config/addon_weapons.lua`.

Use the `ADDON_WEAPONS` list. Each weapon entry should include:

- `code`
- `label`
- `category`
- `attachments`
- optional `unlock`

Simple example:

```lua
{
  code = 'WEAPON_X19',
  label = 'X19',
  category = 'addon_pistols',
  attachments = x19Attachments(),
}
```

For attachment preview support, make sure custom attachments include:

- `component`
- `slot`
- `previewModel`
- `previewAttachBone`

Example:

```lua
{
  label = 'Suppressor 01',
  component = 'COMPONENT_XNEW_SUPP_01',
  slot = 'muzzle',
  previewModel = 'xnew-suppressor1',
  previewAttachBone = 'WAPSupp',
}
```

Restart `exec_framework` after changing weapon config.

## Tints And Presets

- Weapon tints are available from the Attachments menu when the weapon supports them.
- Tints are saved per weapon.
- Saved weapon presets include attachments and tint state.
- Tints and skin/finish components do not show on the preview object.

## Tebex Weapon Unlocks

Use this when a weapon should show in the menu but require purchase before equipping.

Add `unlock` to the weapon entry:

```lua
{
  code = 'WEAPON_X17M',
  label = 'X17 Modular',
  category = 'addon_pistols',
  attachments = x17Attachments('COMPONENT_MARKOMODS_X17M_SLIDE_', 'Slide'),
  unlock = {
    tebexSku = '7439490',
    alwaysLocked = true,
    hint = 'Purchase the X17 Modular on Tebex to unlock.'
  }
}
```

Tebex package command:

```text
exec_weaponlock {sid} WEAPON_X17M unlock
```

Manual admin unlock:

```text
exec_weaponlock <playerId> WEAPON_X17M unlock
```

Manual admin lock:

```text
exec_weaponlock <playerId> WEAPON_X17M lock
```

## Troubleshooting

- Restart `exec_framework` after config changes.
- Restart weapon resources after changing streamed weapon files.
- If add-on attachments work in hand but not preview, check `previewModel` and `previewAttachBone`.
- If a paid weapon is usable by everyone, check `alwaysLocked = true`.
- If Tebex does not unlock a weapon, test `/exec_weaponlock <playerId> WEAPON_CODE unlock` manually first.

## Notes

- `exec_killfeed` should start after this resource.
- `exec_multichar` is optional.
- Compatibility providers are configured in `config/integrations.lua`.
- The database table for paid weapon unlocks is `exec_weapon_unlocks`.
