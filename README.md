# Custom suits

## Installation process
- Download the archive.
- Drop the ***suitc*** folder out of the archive to ***GarrysMod/garrysmod/addons***

## Adding new suits

- Look for the ***custom_suits.json*** file in ***GarrysMod/garrysmod/data***
- Follow the basic structure of the json file.

### Example:
```json
[
  {
    "id": "suit_combine_elite",
    "name": "Elite Combine Suit",
    "category": "Альянс (Костюмы)",
    "model": "models/player/combine_super_soldier.mdl",
    "hands_model": "models/weapons/c_arms_combine.mdl",
    "hp": 150,
    "armor": 150,
    "walk_speed": 170,
    "run_speed": 340,
    "weapons": [
      "weapon_ar2",
      "weapon_pistol"
    ],
    "bodygroups": {},
    "icon": "materials/vgui/suits/combine.png",
    "hud": {
      "default": "combine",
      "allow_player_selection": true,
      "available": [
        "combine"
      ]
    }
  },
  {
    "id": "suit_rebel",
    "name": "Rebel Juggernaut",
    "category": "Повстанцы (Костюмы)",
    "model": "models/player/group03/male_07.mdl",
    "hands_model": "",
    "hp": 200,
    "armor": 50,
    "walk_speed": 150,
    "run_speed": 300,
    "weapons": [
      "weapon_shotgun",
      "weapon_crowbar"
    ],
    "bodygroups": {},
    "icon": "materials/vgui/suits/rebel.png"
  }
]
```
- Copy one of those two, paste and insert your values.
- Do not add any new fields unless you're sure about what you're doing.
- Icons are meant to be contained in the ***suitc/materials/icons*** folder which is not necessery though.

## Notes

- "hands_model" is not essential, the script will try to pick c_hands of a playermodel in the "model" field.
- There is the "get_bg" console command you can use in game to get bodygroups' IDs of your current playermodel.
- To remove a suit type "remove_suit" in the console.