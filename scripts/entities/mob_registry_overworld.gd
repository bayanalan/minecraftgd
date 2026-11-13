## MobRegistryOverworld — remaining 26.3 Overworld mobs: stats, behaviour flags and box rigs (Java model layouts
## recalled, source D; rigs marked "approx" in docs/MOB_PARITY.md where geometry is reconstructed). Flags:
## swims (water AI, out-of-water flop for fish), flies (3D wander), hostile flyers swoop + melee, neutral,
## tame_food, rideable (informational), spawn = in_water for aquatic mobs.
## Contract: DEFS (id -> record incl. "parts"); merged by MobRegistry.get_def.
class_name MobRegistryOverworld

## Java CreakingModel (64 x 64): root (0, 24, 0) > upper_body (-1, -19, 0) > head (-3, -11, 0) with its crown and two
## branch planes, body (0, -7, 1) two boxes, right_arm (-7, -9.5, 1.5) long arm + hand, left_arm (6, -9, 0.5) arm +
## shoulder + hand; legs on the root: left (1.5, -16, 0.5) with a root-foot plane, right (-1, -17.5, 0.5) with its foot
## and knee. Pivots below are absolute (the hierarchy flattened); extra boxes share their part's pivot.
const CREAKING := [
	["head", [-4, -6, 0], [-3, -10, -3], [6, 10, 6], [0, 0], 0, 0, 0, 0.0,
		[["crown", [-3, -13, -3], [6, 3, 6], [28, 31], 0.0], ["branch_r", [3, -13, 0], [9, 14, 0], [12, 40], 0.0], ["branch_l", [-12, -14, 0], [9, 14, 0], [34, 12], 0.0]]],
	["body", [-1, -2, 1], [0, -3, -3], [6, 13, 5], [0, 16], 0, 0, 0, 0.0, [["chest", [-6, -4, -3], [6, 7, 5], [24, 0], 0.0]]],
	["arm0", [-8, -4.5, 1.5], [-2, -1.5, -1.5], [3, 21, 3], [22, 13], 0, 0, 0, 0.0, [["hand0", [-2, 19.5, -1.5], [3, 4, 3], [46, 0], 0.0]]],
	["arm1", [5, -4, 0.5], [0, -1, -1.5], [3, 16, 3], [30, 40], 0, 0, 0, 0.0, [["shoulder1", [0, -5, -1.5], [3, 4, 3], [52, 12], 0.0], ["hand1", [0, 15, -1.5], [3, 4, 3], [52, 19], 0.0]]],
	["leg0", [-1, 6.5, 0.5], [-3, -1.5, -1.5], [3, 19, 3], [0, 34], 0, 0, 0, 0.0, [["foot0", [-3.4, 17.2, -4.5], [5, 0, 9], [45, 55], 0.0], ["knee0", [-3, -4.5, -1.5], [3, 3, 3], [12, 34], 0.0]]],
	["leg1", [1.5, 8, 0.5], [-1.5, 0, -1.5], [3, 16, 3], [42, 40], 0, 0, 0, 0.0, [["foot1", [-1.5, 15.7, -4.5], [5, 0, 9], [45, 55], 0.0]]],
]

## Java VillagerModel (64 x 64): head + hat layer (0.51) + hat rim (rotated -90 x) + nose, body + jacket (8 x 20 x 6,
## 0.5), crossed arms = two 4 x 8 x 4 side boxes and an 8 x 4 x 4 middle at xRot -0.75 rad, legs.
const VILLAGER := [["head", [0, 0, 0], [-4, -10, -4], [8, 10, 8], [0, 0], 0, 0, 0, 0.0, [["hat", [-4, -10, -4], [8, 10, 8], [32, 0], 0.51]]],
	["hat_rim", [0, 0, 0], [-8, -8, -6], [16, 16, 1], [30, 47], -90], ["nose", [0, -2, 0], [-1, -1, -6], [2, 4, 2], [24, 0], 0],
	["body", [0, 0, 0], [-4, 0, -3], [8, 12, 6], [16, 20], 0, 0, 0, 0.0, [["jacket", [-4, 0, -3], [8, 20, 6], [0, 38], 0.5]]],
	["arms", [0, 3, -1], [-8, -2, -2], [4, 8, 4], [44, 22], -42.97, 0, 0, 0.0, [["arms_r", [4, -2, -2], [4, 8, 4], [44, 22], 0.0], ["arms_mid", [-4, 2, -2], [8, 4, 4], [40, 38], 0.0]]],
	["leg0", [-2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0], ["leg1", [2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0]]
const ILLAGER := [["head", [0, 0, 0], [-4, -10, -4], [8, 10, 8], [0, 0], 0], ["nose", [0, -2, 0], [-1, -1, -6], [2, 4, 2], [24, 0], 0],
	["body", [0, 0, 0], [-4, 0, -3], [8, 12, 6], [16, 20], 0], ["arm0", [-5, 2, 0], [-3, -2, -2], [4, 12, 4], [40, 46], 0],
	["arm1", [5, 2, 0], [-1, -2, -2], [4, 12, 4], [40, 46], 0], ["leg0", [-2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0],
	["leg1", [2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0]]
const IRON_GOLEM := [["head", [0, -7, -2], [-4, -12, -5.5], [8, 10, 8], [0, 0], 0], ["nose", [0, -7, -2], [-1, -5, -7.5], [2, 4, 2], [24, 0], 0],
	["body", [0, -7, 0], [-9, -2, -6], [18, 12, 11], [0, 40], 0], ["waist", [0, -7, 0], [-4.5, 10, -3], [9, 5, 6], [0, 70], 0],
	["arm0", [0, -7, 0], [-13, -2.5, -3], [4, 30, 6], [60, 21], 0], ["arm1", [0, -7, 0], [9, -2.5, -3], [4, 30, 6], [60, 58], 0],
	["leg0", [-4, 11, 0], [-3.5, -3, -3], [6, 16, 5], [37, 0], 0], ["leg1", [5, 11, 0], [-3.5, -3, -3], [6, 16, 5], [60, 0], 0]]
const WOLF := [["head", [-1, 13.5, -7], [-2, -3, -2], [6, 6, 4], [0, 0], 0], ["ear0", [-1, 13.5, -7], [-2, -5, 0], [2, 2, 1], [16, 14], 0],
	["ear1", [-1, 13.5, -7], [2, -5, 0], [2, 2, 1], [16, 14], 0], ["snout", [-1, 13.5, -7], [-0.5, -0.02, -5], [3, 3, 4], [0, 10], 0],
	["body", [0, 14, 2], [-3, -2, -3], [6, 9, 6], [18, 14], 90], ["mane", [-1, 14, -3], [-3, -3, -3], [8, 6, 7], [21, 0], 90],
	["leg0", [-2.5, 16, 7], [0, 0, -1], [2, 8, 2], [0, 18], 0], ["leg1", [0.5, 16, 7], [0, 0, -1], [2, 8, 2], [0, 18], 0],
	["leg2", [-2.5, 16, -4], [0, 0, -1], [2, 8, 2], [0, 18], 0], ["leg3", [0.5, 16, -4], [0, 0, -1], [2, 8, 2], [0, 18], 0],
	["tail", [-1, 12, 8], [0, 0, -1], [2, 8, 2], [9, 18], 30]]
## Java OcelotModel / CatModel (64 x 32): head with nose (y -0.001: no coplanar face with the head bottom) and ears,
## body rotated 90, two tail segments (tail2 deflated 0.02), hind / front legs.
const CAT := [["head", [0, 15, -9], [-2.5, -2, -3], [5, 4, 5], [0, 0], 0], ["nose", [0, 15, -9], [-1.5, -0.001, -4], [3, 2, 2], [0, 24], 0],
	["ear0", [0, 15, -9], [-2, -3, 0], [1, 1, 2], [0, 10], 0], ["ear1", [0, 15, -9], [1, -3, 0], [1, 1, 2], [6, 10], 0],
	["body", [0, 12, -10], [-2, 3, -8], [4, 16, 6], [20, 0], 90], ["tail1", [0, 15, 8], [-0.5, 0, 0], [1, 8, 1], [0, 15], 51.566],
	["tail2", [0, 20, 14], [-0.5, 0, 0], [1, 8, 1], [4, 15], 98.996, 0, 0, -0.02],
	["leg0", [1.1, 18, 5], [-1, 0, 1], [2, 6, 2], [8, 13], 0], ["leg1", [-1.1, 18, 5], [-1, 0, 1], [2, 6, 2], [8, 13], 0],
	["leg2", [1.2, 14.1, -5], [-1, 0, 0], [2, 10, 2], [40, 0], 0], ["leg3", [-1.2, 14.1, -5], [-1, 0, 0], [2, 10, 2], [40, 0], 0]]
const HORSE := [["body", [0, 11, 5], [-5, -8, -17], [10, 10, 22], [0, 32], 0], ["neck", [0, 4, -12], [-2.05, -6, -2], [4, 12, 7], [0, 35], 30],
	["head", [0, 4, -12], [-3, -11, -2], [6, 5, 7], [0, 13], 30], ["muzzle", [0, 4, -12], [-2, -11, -7], [4, 5, 5], [0, 25], 30],
	["leg0", [4, 14, 7], [-3, -1.01, -1], [4, 11, 4], [48, 21], 0], ["leg1", [-4, 14, 7], [-1, -1.01, -1], [4, 11, 4], [48, 21], 0],
	["leg2", [4, 14, -10], [-3, -1.01, -1.9], [4, 11, 4], [48, 21], 0], ["leg3", [-4, 14, -10], [-1, -1.01, -1.9], [4, 11, 4], [48, 21], 0],
	["tail", [0, 4, 11], [-1.5, 0, 0], [3, 14, 4], [42, 36], 30]]
const BEE := [["body", [0, 19, 0], [-3.5, -4, -5], [7, 7, 10], [0, 0], 0], ["stinger", [0, 19, 0], [0, -1, 5], [0, 1, 2], [26, 7], 0],
	["wing0", [-1.5, 15, -3], [-9, 0, 0], [9, 0, 6], [0, 18], 0], ["wing1", [1.5, 15, -3], [0, 0, 0], [9, 0, 6], [9, 24], 0],
	["leg0", [1.5, 22, -2], [-5, 0, 0], [7, 2, 0], [26, 1], 0], ["leg1", [1.5, 22, 0], [-5, 0, 0], [7, 2, 0], [26, 3], 0], ["leg2", [1.5, 22, 2], [-5, 0, 0], [7, 2, 0], [26, 5], 0]]
const RABBIT := [["body", [0, 19, 8], [-3, -2, -10], [6, 5, 10], [0, 0], 20], ["head", [0, 16, -1], [-2.5, -4, -5], [5, 4, 5], [32, 0], 0],
	["ear0", [0, 16, -1], [-2.5, -9, -1], [2, 5, 1], [52, 0], 0], ["ear1", [0, 16, -1], [0.5, -9, -1], [2, 5, 1], [58, 0], 0],
	["leg0", [3, 17.5, 3.7], [-1, 0, 0], [2, 4, 5], [16, 15], -20], ["leg1", [-3, 17.5, 3.7], [-1, 0, 0], [2, 4, 5], [26, 15], -20],
	["leg2", [3, 17, -1], [-1, 0, -1], [2, 7, 2], [8, 15], -10], ["leg3", [-3, 17, -1], [-1, 0, -1], [2, 7, 2], [0, 15], -10]]
const SQUID := [["body", [0, 8, 0], [-6, -8, -6], [12, 16, 12], [0, 0], 0],
	["tent0", [5, 15, 0], [-1, 0, -1], [2, 18, 2], [48, 0], 0], ["tent1", [3.5, 15, 3.5], [-1, 0, -1], [2, 18, 2], [48, 0], 0],
	["tent2", [0, 15, 5], [-1, 0, -1], [2, 18, 2], [48, 0], 0], ["tent3", [-3.5, 15, 3.5], [-1, 0, -1], [2, 18, 2], [48, 0], 0],
	["tent4", [-5, 15, 0], [-1, 0, -1], [2, 18, 2], [48, 0], 0], ["tent5", [-3.5, 15, -3.5], [-1, 0, -1], [2, 18, 2], [48, 0], 0],
	["tent6", [0, 15, -5], [-1, 0, -1], [2, 18, 2], [48, 0], 0], ["tent7", [3.5, 15, -3.5], [-1, 0, -1], [2, 18, 2], [48, 0], 0]]
const COD := [["body", [0, 22, 0], [-1, -2, 0], [2, 4, 7], [0, 0], 0], ["head", [0, 22, 0], [-1, -2, -3], [2, 4, 3], [11, 0], 0],
	["nose", [0, 22, 0], [-1, -2, -1], [2, 3, 1], [0, 0], 0], ["fin0", [0, 20, 0], [0, -1, 0], [0, 1, 6], [20, 1], 0], ["tail", [0, 22, 7], [0, -2, 0], [0, 4, 4], [22, 3], 0]]
const SALMON := [["body", [0, 20, 0], [-1.5, -2.5, 0], [3, 5, 8], [0, 0], 0], ["head", [0, 20, 0], [-1, -2, -3], [2, 4, 3], [22, 0], 0],
	["tail", [0, 20, 8], [-1.5, -2.5, 0], [3, 5, 8], [0, 13], 0], ["fin", [0, 20, 8], [0, 2.5, 0], [0, 4, 8], [20, 10], 0]]
const BAT := [["head", [0, 17, 0], [-2, -3, -1], [4, 3, 2], [0, 0], 0], ["body", [0, 17, 0], [-1.5, 0, -1], [3, 5, 2], [0, 7], 0],
	["wing0", [-1.5, 17, 0], [-2, 0, 0], [2, 7, 0], [12, 0], 0], ["wing1", [1.5, 17, 0], [0, 0, 0], [2, 7, 0], [12, 7], 0]]
const PARROT := [["body", [0, 16.5, -3], [-1.5, 0, -1.5], [3, 6, 3], [2, 8], 28], ["tail", [0, 21.1, 1.2], [-1.5, -1, -1], [3, 4, 1], [22, 1], 60],
	["wing0", [1.5, 16.94, -2.76], [-0.5, 0, -1.5], [1, 5, 3], [19, 8], -12], ["wing1", [-1.5, 16.94, -2.76], [-0.5, 0, -1.5], [1, 5, 3], [19, 8], -12],
	["head", [0, 15.69, -2.76], [-1, -1.5, -1], [2, 3, 2], [2, 2], 0], ["beak", [0, 15.69, -2.76], [-0.5, -1, -2], [1, 2, 1], [11, 7], 0],
	["leg0", [1, 22, -1.05], [-0.5, 0, -0.5], [1, 2, 1], [14, 18], 0], ["leg1", [-1, 22, -1.05], [-0.5, 0, -0.5], [1, 2, 1], [14, 18], 0]]
const SNOW_GOLEM := [["head", [0, 4, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0], ["body", [0, 4, 0], [-5, 0, -5], [10, 10, 10], [0, 16], 0],
	["base", [0, 13, 0], [-6, 0, -6], [12, 12, 12], [0, 36], 0], ["arm0", [-5, 6, 1], [-1, 0, -1], [12, 2, 2], [32, 0], 0],
	["arm1", [5, 6, -1], [-1, 0, -1], [12, 2, 2], [32, 0], 0]]
const PHANTOM := [["body", [0, 0, 0], [-3, -2, -8], [5, 3, 9], [0, 8], -6], ["head", [0, 1, -7], [-4, -2, -5], [7, 3, 5], [0, 0], 11],
	["wing0", [2, -2, -8], [0, 0, 0], [6, 2, 9], [23, 12], 0], ["wing1", [-3, -2, -8], [-6, 0, 0], [6, 2, 9], [16, 24], 0],
	["tail", [0, -2, 1], [-2, 0, 0], [3, 2, 6], [3, 20], -5]]
const GUARDIAN := [["head", [0, 0, 0], [-6, 10, -8], [12, 12, 16], [0, 0], 0], ["side0", [0, 0, 0], [-8, 10, -6], [2, 12, 12], [0, 28], 0],
	["side1", [0, 0, 0], [6, 10, -6], [2, 12, 12], [0, 28], 0], ["top", [0, 0, 0], [-6, 8, -6], [12, 2, 12], [16, 40], 0],
	["bottom", [0, 0, 0], [-6, 22, -6], [12, 2, 12], [16, 40], 0], ["eye", [0, 0, 0], [-1, 15, 0], [2, 2, 1], [8, 0], 0],
	["tail0", [-2, 14, 7], [0, 0, 0], [4, 4, 8], [40, 0], 0], ["tail1", [-1.5, 15.5, 14], [0, 0, 0], [3, 3, 7], [0, 54], 0]]
const POLAR_BEAR := [["head", [0, 10, -16], [-3.5, -3, -3], [7, 7, 7], [0, 0], 0], ["snout", [0, 10, -16], [-2.5, 1, -6], [5, 3, 3], [0, 44], 0],
	["body", [-2, 9, 12], [-5, -13, -7], [14, 14, 11], [0, 19], 90], ["leg0", [-4.5, 14, 6], [-2, 0, -2], [4, 10, 8], [50, 22], 0],
	["leg1", [4.5, 14, 6], [-2, 0, -2], [4, 10, 8], [50, 22], 0], ["leg2", [-3.5, 14, -8], [-2, 0, -2], [4, 10, 6], [50, 40], 0],
	["leg3", [3.5, 14, -8], [-2, 0, -2], [4, 10, 6], [50, 40], 0]]
const LLAMA := [["head", [0, 7, -6], [-2, -14, -10], [4, 4, 9], [0, 0], 0], ["neck", [0, 7, -6], [-4, -16, -6], [8, 18, 6], [0, 14], 0],
	["body", [0, 5, 2], [-6, -10, -7], [12, 18, 10], [29, 0], 90], ["leg0", [-3.5, 10, 6], [-2, 0, -2], [4, 14, 4], [29, 29], 0],
	["leg1", [3.5, 10, 6], [-2, 0, -2], [4, 14, 4], [29, 29], 0], ["leg2", [-3.5, 10, -5], [-2, 0, -2], [4, 14, 4], [29, 29], 0],
	["leg3", [3.5, 10, -5], [-2, 0, -2], [4, 14, 4], [29, 29], 0]]
const TURTLE := [["head", [0, 19, -10], [-3, -1, -3], [6, 5, 6], [3, 0], 0], ["body", [0, 11, -10], [-9.5, 3, -10], [19, 20, 6], [7, 37], 90],
	["leg0", [-3.5, 22, 11], [-2, 0, 0], [4, 1, 10], [1, 23], 0], ["leg1", [3.5, 22, 11], [-2, 0, 0], [4, 1, 10], [1, 12], 0],
	["leg2", [-5, 21, -4], [-13, 0, -2], [13, 1, 5], [27, 30], 0], ["leg3", [5, 21, -4], [0, 0, -2], [13, 1, 5], [27, 24], 0]]
const DOLPHIN := [["body", [0, 22, -5], [-4, -7, 0], [8, 7, 13], [22, 0], 0], ["head", [0, 22, -5], [-4, -3, -3], [8, 7, 6], [0, 0], 0],
	["nose", [0, 22, -5], [-1, 2, -7], [2, 2, 4], [0, 13], 0], ["fin", [0, 22, -5], [-0.5, -8, 4], [1, 4, 5], [51, 0], 0],
	["tail", [0, 19, 8], [-2, -2.5, 0], [4, 5, 11], [0, 19], 0], ["tail_fin", [0, 19, 18], [-5, 0, 0], [10, 1, 6], [19, 20], 0]]
const FOX := [["head", [-1, 16.5, -3], [-3, -2, -5], [8, 6, 6], [1, 5], 0], ["ear0", [-1, 16.5, -3], [-3, -4, -4], [2, 2, 1], [8, 1], 0],
	["ear1", [-1, 16.5, -3], [3, -4, -4], [2, 2, 1], [15, 1], 0], ["snout", [-1, 16.5, -3], [-1, 2.01, -8], [4, 2, 3], [6, 18], 0],
	["body", [0, 16, -6], [-3, 3.999, -3.5], [6, 11, 6], [24, 15], 90], ["leg0", [-5, 17.5, 7], [2, 0.5, -1], [2, 6, 2], [13, 24], 0],
	["leg1", [-1, 17.5, 7], [2, 0.5, -1], [2, 6, 2], [4, 24], 0], ["leg2", [-5, 17.5, 0], [2, 0.5, -1], [2, 6, 2], [13, 24], 0],
	["leg3", [-1, 17.5, 0], [2, 0.5, -1], [2, 6, 2], [4, 24], 0], ["tail", [-4, 15, -1], [2, 0, -1], [4, 9, 5], [30, 0], 90]]
const GOAT := [["head", [1, 14, 0], [-3, -4, -8], [5, 7, 10], [2, 61], 0], ["body", [0, 24, 0], [-4, -17, -7], [9, 11, 16], [1, 1], 0],
	["leg0", [1, 14, 4], [0, 4, 0], [3, 6, 3], [49, 2], 0], ["leg1", [-3, 14, 4], [0, 4, 0], [3, 6, 3], [35, 2], 0],
	["leg2", [1, 14, -6], [0, 4, 0], [3, 6, 3], [49, 29], 0], ["leg3", [-3, 14, -6], [0, 4, 0], [3, 6, 3], [35, 29], 0]]
const PANDA := [["head", [0, 11.5, -17], [-6.5, -5, -4], [13, 10, 9], [0, 6], 0], ["body", [0, 14, 0], [-9.5, -13, -6.5], [19, 26, 13], [0, 25], 90],
	["leg0", [-5.5, 15, 9], [-3, 0, -3], [6, 9, 6], [40, 0], 0], ["leg1", [5.5, 15, 9], [-3, 0, -3], [6, 9, 6], [40, 0], 0],
	["leg2", [-5.5, 15, -9], [-3, 0, -3], [6, 9, 6], [40, 0], 0], ["leg3", [5.5, 15, -9], [-3, 0, -3], [6, 9, 6], [40, 0], 0]]
const AXOLOTL := [["body", [0, 20, 5], [-4, -2, -9], [8, 4, 10], [0, 11], 0], ["head", [0, 20, -4], [-4, -3, -5], [8, 5, 5], [0, 1], 0],
	["leg0", [-3.5, 21, 4], [-2, 0, 0], [3, 5, 0], [2, 13], 0], ["leg1", [3.5, 21, 4], [-1, 0, 0], [3, 5, 0], [2, 13], 0],
	["leg2", [-3.5, 21, -3], [-2, 0, 0], [3, 5, 0], [2, 13], 0], ["leg3", [3.5, 21, -3], [-1, 0, 0], [3, 5, 0], [2, 13], 0],
	["tail", [0, 20, 6], [0, -3, 0], [0, 5, 12], [2, 19], 0]]
const FROG := [["body", [0, 22, 0], [-3.5, -2, -8], [7, 3, 9], [3, 1], 0], ["head", [0, 20, -3], [-3.5, -2, -5], [7, 3, 9], [23, 13], 0],
	["leg0", [-2, 22, 3], [-1.5, 0, -1.5], [3, 3, 4], [14, 25], 0], ["leg1", [2, 22, 3], [-1.5, 0, -1.5], [3, 3, 4], [0, 25], 0],
	["leg2", [-4, 21, -4], [-1, 0, -1], [2, 3, 3], [0, 32], 0], ["leg3", [4, 21, -4], [-1, 0, -1], [2, 3, 3], [8, 32], 0]]
const RAVAGER := [["head", [0, -7, -1.5], [-8, -20, -14], [16, 20, 16], [0, 0], 0], ["body", [0, 1, 2], [-7, -10, -7], [14, 16, 20], [0, 55], 90],
	["leg0", [-8, -13, 18], [-4, 0, -4], [8, 37, 8], [96, 0], 0], ["leg1", [8, -13, 18], [-4, 0, -4], [8, 37, 8], [96, 0], 0],
	["leg2", [-8, -13, -4], [-4, 0, -4], [8, 37, 8], [64, 0], 0], ["leg3", [8, -13, -4], [-4, 0, -4], [8, 37, 8], [64, 0], 0]]
const VEX := [["head", [0, 0, 0], [-2.5, -5, -2.5], [5, 5, 5], [0, 0], 0], ["body", [0, 0, 0], [-1.5, 0, -1], [3, 4, 2], [0, 10], 0],
	["arm0", [-1.75, 0.25, 0], [-1.25, -0.5, -1], [2, 4, 2], [23, 0], 0], ["arm1", [1.75, 0.25, 0], [-0.75, -0.5, -1], [2, 4, 2], [23, 6], 0],
	["wing0", [-0.5, 1, 1], [-8, 0, 0], [8, 5, 1], [16, 14], 0], ["wing1", [0.5, 1, 1], [0, 0, 0], [8, 5, 1], [16, 14], 0]]
const TADPOLE := [["body", [0, 22, -3], [-1.5, -1, 0], [3, 2, 3], [0, 0], 0], ["tail", [0, 22, 0], [0, -1, 0], [0, 2, 7], [0, 0], 0]]
const ALLAY := [["head", [0, 15, 0], [-2.5, -5, -2.5], [5, 5, 5], [0, 0], 0], ["body", [0, 15, 0], [-1.5, 0, -1], [3, 4, 2], [0, 10], 0],
	["arm0", [-1.75, 15.5, 0], [-0.75, -0.5, -1], [1, 4, 2], [23, 0], 0], ["arm1", [1.75, 15.5, 0], [-0.25, -0.5, -1], [1, 4, 2], [23, 6], 0],
	["wing0", [-0.5, 16, 1], [-8, 0, 0], [8, 5, 1], [16, 14], 0], ["wing1", [0.5, 16, 1], [0, 0, 0], [8, 5, 1], [16, 14], 0]]
const WITHER := [["base", [0, 0, 0], [-10, 3.9, -0.5], [20, 3, 3], [0, 16], 0], ["spine", [-2, 6.9, -0.5], [0, 0, 0], [3, 10, 3], [0, 22], 0],
	["tail", [-2, 16.9, -0.5], [0, 0, 0], [3, 6, 3], [12, 22], 0], ["head0", [0, 0, 0], [-4, -4, -4], [8, 8, 8], [0, 0], 0],
	["head1", [-8, 4, 0], [-4, -4, -4], [6, 6, 6], [32, 0], 0], ["head2", [10, 4, 0], [-4, -4, -4], [6, 6, 6], [32, 0], 0]]
const CHICKEN_LIKE := [["body", [0, 16, 0], [-3, -4, -3], [6, 8, 6], [0, 9], 90], ["head", [0, 15, -4], [-2, -6, -2], [4, 6, 3], [0, 0], 0]]

const DEFS := {
	"villager": {"hp": 20, "speed": 0.25, "w": 0.6, "h": 1.95, "kind": "passive", "trader": true, "tex": "entity/villager/villager", "tex_size": [64, 64], "xp": [0, 0], "parts": VILLAGER},
	"wandering_trader": {"hp": 20, "speed": 0.25, "w": 0.6, "h": 1.95, "kind": "passive", "trader": true, "tex": "entity/wandering_trader/wandering_trader", "tex_size": [64, 64], "xp": [0, 0], "parts": VILLAGER},
	"zombie_villager": {"hp": 20, "speed": 0.23, "w": 0.6, "h": 1.95, "kind": "hostile", "burns": true, "attack": 3.0, "tex": "entity/zombie_villager/zombie_villager", "tex_size": [64, 64], "xp": [5, 5], "parts": ILLAGER},
	"witch": {"hp": 26, "speed": 0.25, "w": 0.6, "h": 1.95, "kind": "hostile", "ranged_potion": true, "tex": "entity/witch/witch", "tex_size": [64, 128], "xp": [5, 5], "parts": VILLAGER},
	"pillager": {"hp": 24, "speed": 0.35, "w": 0.6, "h": 1.95, "kind": "hostile", "ranged": true, "tex": "entity/illager/pillager", "tex_size": [64, 64], "xp": [5, 5], "parts": ILLAGER},
	"vindicator": {"hp": 24, "speed": 0.35, "w": 0.6, "h": 1.95, "kind": "hostile", "attack": 13.0, "tex": "entity/illager/vindicator", "tex_size": [64, 64], "xp": [5, 5], "parts": ILLAGER},
	"evoker": {"hp": 24, "speed": 0.5, "w": 0.6, "h": 1.95, "kind": "hostile", "summons_vex": true, "tex": "entity/illager/evoker", "tex_size": [64, 64], "xp": [10, 10], "parts": ILLAGER},
	"illusioner": {"hp": 32, "speed": 0.5, "w": 0.6, "h": 1.95, "kind": "hostile", "ranged": true, "tex": "entity/illager/illusioner", "tex_size": [64, 64], "xp": [5, 5], "parts": ILLAGER},
	"ravager": {"hp": 100, "speed": 0.3, "w": 1.95, "h": 2.2, "kind": "hostile", "attack": 12.0, "tex": "entity/illager/ravager", "tex_size": [128, 128], "xp": [20, 20], "parts": RAVAGER},
	"vex": {"hp": 14, "speed": 0.6, "w": 0.4, "h": 0.8, "kind": "hostile", "flies": true, "small_flyer": true, "attack": 9.0, "tex": "entity/illager/vex", "tex_size": [32, 32], "xp": [3, 3], "parts": VEX},
	"iron_golem": {"hp": 100, "speed": 0.25, "w": 1.4, "h": 2.7, "kind": "passive", "golem": true, "attack": 15.0, "tex": "entity/iron_golem/iron_golem", "tex_size": [128, 128], "xp": [0, 0], "parts": IRON_GOLEM},
	"snow_golem": {"hp": 4, "speed": 0.2, "w": 0.7, "h": 1.9, "kind": "passive", "golem": true, "water_hurts": true, "tex": "entity/snow_golem/snow_golem", "tex_size": [64, 64], "xp": [0, 0], "parts": SNOW_GOLEM},
	"wolf": {"hp": 8, "speed": 0.3, "w": 0.6, "h": 0.85, "kind": "passive", "tame_food": "bone", "tex": "entity/wolf/wolf", "tex_size": [64, 32], "food": ["beef", "porkchop", "chicken", "mutton", "rabbit"], "xp": [1, 3], "parts": WOLF},
	"cat": {"hp": 10, "speed": 0.3, "w": 0.6, "h": 0.7, "kind": "passive", "tame_food": "cod", "tex": "entity/cat/cat_tabby", "tex_size": [64, 32], "food": ["cod", "salmon"], "xp": [1, 3], "parts": CAT},
	"ocelot": {"hp": 10, "speed": 0.3, "w": 0.6, "h": 0.7, "kind": "passive", "tex": "entity/cat/ocelot", "tex_size": [64, 32], "food": ["cod", "salmon"], "xp": [1, 3], "parts": CAT},
	"horse": {"hp": 22, "speed": 0.225, "w": 1.4, "h": 1.6, "kind": "passive", "rideable": true, "tex": "entity/horse/horse_brown", "tex_size": [64, 64], "food": ["golden_carrot", "golden_apple"], "xp": [1, 3], "parts": HORSE},
	"donkey": {"hp": 20, "speed": 0.175, "w": 1.4, "h": 1.5, "kind": "passive", "rideable": true, "tex": "entity/horse/donkey", "tex_size": [64, 64], "food": ["golden_carrot", "golden_apple"], "xp": [1, 3], "parts": HORSE},
	"mule": {"hp": 20, "speed": 0.175, "w": 1.4, "h": 1.6, "kind": "passive", "rideable": true, "tex": "entity/horse/mule", "tex_size": [64, 64], "xp": [1, 3], "parts": HORSE},
	"skeleton_horse": {"hp": 15, "speed": 0.2, "w": 1.4, "h": 1.6, "kind": "passive", "tex": "entity/horse/horse_skeleton", "tex_size": [64, 64], "xp": [1, 3], "parts": HORSE},
	"zombie_horse": {"hp": 15, "speed": 0.2, "w": 1.4, "h": 1.6, "kind": "passive", "tex": "entity/horse/horse_zombie", "tex_size": [64, 64], "xp": [1, 3], "parts": HORSE},
	"camel": {"hp": 32, "speed": 0.09, "w": 1.7, "h": 2.375, "kind": "passive", "rideable": true, "tex": "entity/camel/camel", "tex_size": [128, 128], "food": ["cactus"], "xp": [1, 3], "parts": HORSE, "scale": 1.4},
	"camel_husk": {"hp": 32, "speed": 0.09, "w": 1.7, "h": 2.375, "kind": "hostile", "tex": "entity/camel/camel_husk", "tex_size": [128, 128], "attack": 4.0, "xp": [5, 5], "parts": HORSE, "scale": 1.4},
	"llama": {"hp": 22, "speed": 0.175, "w": 0.9, "h": 1.87, "kind": "passive", "spits": true, "tex": "entity/llama/llama_creamy", "tex_size": [128, 64], "food": ["wheat", "hay_block"], "xp": [1, 3], "parts": LLAMA},
	"trader_llama": {"hp": 22, "speed": 0.175, "w": 0.9, "h": 1.87, "kind": "passive", "spits": true, "tex": "entity/llama/llama_creamy", "tex_size": [128, 64], "xp": [1, 3], "parts": LLAMA},
	"mooshroom": {"hp": 10, "speed": 0.2, "w": 0.9, "h": 1.4, "kind": "passive", "tex": "entity/cow/mooshroom_red", "tex_size": [64, 64], "food": ["wheat"], "xp": [1, 3], "rig_of": "cow"},
	"bee": {"hp": 10, "speed": 0.3, "w": 0.7, "h": 0.6, "kind": "passive", "flies": true, "small_flyer": true, "neutral_sting": true, "tex": "entity/bee/bee", "tex_size": [64, 64], "food": ["dandelion", "poppy", "sunflower"], "xp": [1, 3], "parts": BEE},
	"fox": {"hp": 10, "speed": 0.3, "w": 0.6, "h": 0.7, "kind": "passive", "tex": "entity/fox/fox", "tex_size": [48, 32], "food": ["sweet_berries", "glow_berries"], "xp": [1, 3], "parts": FOX},
	"rabbit": {"hp": 3, "speed": 0.3, "w": 0.4, "h": 0.5, "kind": "passive", "hops": false, "tex": "entity/rabbit/rabbit_brown", "tex_size": [64, 32], "food": ["carrot", "golden_carrot", "dandelion"], "xp": [1, 3], "parts": RABBIT},
	"goat": {"hp": 10, "speed": 0.2, "w": 0.9, "h": 1.3, "kind": "passive", "rams": true, "tex": "entity/goat/goat", "tex_size": [64, 64], "food": ["wheat"], "xp": [1, 3], "parts": GOAT},
	"panda": {"hp": 20, "speed": 0.15, "w": 1.3, "h": 1.25, "kind": "passive", "tex": "entity/panda/panda", "tex_size": [64, 64], "food": ["bamboo"], "xp": [1, 3], "parts": PANDA},
	"polar_bear": {"hp": 30, "speed": 0.25, "w": 1.4, "h": 1.4, "kind": "passive", "defends": true, "attack": 6.0, "tex": "entity/bear/polarbear", "tex_size": [128, 64], "xp": [1, 3], "parts": POLAR_BEAR},
	"turtle": {"hp": 30, "speed": 0.25, "w": 1.2, "h": 0.4, "kind": "passive", "amphibious": true, "tex": "entity/turtle/turtle", "tex_size": [128, 64], "food": ["seagrass"], "xp": [1, 3], "parts": TURTLE},
	"armadillo": {"hp": 12, "speed": 0.14, "w": 0.7, "h": 0.65, "kind": "passive", "tex": "entity/armadillo/armadillo", "tex_size": [64, 64], "food": ["spider_eye"], "xp": [1, 3], "parts": PANDA, "scale": 0.45},
	"sniffer": {"hp": 14, "speed": 0.1, "w": 1.9, "h": 1.75, "kind": "passive", "tex": "entity/sniffer/sniffer", "tex_size": [192, 192], "food": ["torchflower_seeds"], "xp": [1, 3], "parts": POLAR_BEAR, "scale": 1.3},
	"axolotl": {"hp": 14, "speed": 1.0, "w": 0.75, "h": 0.42, "kind": "passive", "swims": true, "amphibious": true, "tex": "entity/axolotl/axolotl_lucy", "tex_size": [64, 64], "food": ["tropical_fish_bucket"], "xp": [1, 3], "spawn": "in_water", "parts": AXOLOTL},
	"frog": {"hp": 10, "speed": 1.0, "w": 0.5, "h": 0.5, "kind": "passive", "amphibious": true, "tex": "entity/frog/frog_temperate", "tex_size": [48, 48], "food": ["slime_ball"], "xp": [1, 3], "parts": FROG},
	"tadpole": {"hp": 6, "speed": 1.0, "w": 0.4, "h": 0.3, "kind": "passive", "swims": true, "fish": true, "tex": "entity/tadpole/tadpole", "tex_size": [16, 16], "xp": [0, 0], "spawn": "in_water", "parts": TADPOLE},
	"squid": {"hp": 10, "speed": 0.4, "w": 0.8, "h": 0.8, "kind": "passive", "swims": true, "fish": true, "tex": "entity/squid/squid", "tex_size": [64, 32], "xp": [1, 3], "spawn": "in_water", "parts": SQUID},
	"glow_squid": {"hp": 10, "speed": 0.4, "w": 0.8, "h": 0.8, "kind": "passive", "swims": true, "fish": true, "tex": "entity/squid/glow_squid", "tex_size": [64, 32], "xp": [1, 3], "spawn": "in_water", "parts": SQUID},
	"cod": {"hp": 3, "speed": 1.0, "w": 0.5, "h": 0.3, "kind": "passive", "swims": true, "fish": true, "tex": "entity/fish/cod", "tex_size": [32, 32], "xp": [1, 3], "spawn": "in_water", "parts": COD},
	"salmon": {"hp": 3, "speed": 1.0, "w": 0.7, "h": 0.4, "kind": "passive", "swims": true, "fish": true, "tex": "entity/fish/salmon", "tex_size": [32, 32], "xp": [1, 3], "spawn": "in_water", "parts": SALMON},
	"tropical_fish": {"hp": 3, "speed": 1.0, "w": 0.5, "h": 0.4, "kind": "passive", "swims": true, "fish": true, "tex": "entity/fish/tropical_a", "tex_size": [32, 32], "xp": [1, 3], "spawn": "in_water", "parts": COD},
	"pufferfish": {"hp": 3, "speed": 1.0, "w": 0.7, "h": 0.7, "kind": "passive", "swims": true, "fish": true, "poisons": true, "tex": "entity/fish/pufferfish", "tex_size": [32, 32], "xp": [1, 3], "spawn": "in_water", "parts": COD},
	"dolphin": {"hp": 10, "speed": 1.2, "w": 0.9, "h": 0.6, "kind": "passive", "swims": true, "tex": "entity/dolphin/dolphin", "tex_size": [64, 64], "xp": [1, 3], "spawn": "in_water", "parts": DOLPHIN},
	"guardian": {"hp": 30, "speed": 0.5, "w": 0.85, "h": 0.85, "kind": "hostile", "swims": true, "laser": true, "attack": 6.0, "tex": "entity/guardian/guardian", "tex_size": [64, 64], "xp": [10, 10], "spawn": "in_water", "parts": GUARDIAN},
	"elder_guardian": {"hp": 80, "speed": 0.3, "w": 2.0, "h": 2.0, "kind": "hostile", "swims": true, "laser": true, "attack": 8.0, "tex": "entity/guardian/guardian_elder", "tex_size": [64, 64], "xp": [10, 10], "scale": 2.35, "spawn": "in_water", "parts": GUARDIAN},
	"nautilus": {"hp": 15, "speed": 1.0, "w": 0.875, "h": 0.95, "kind": "passive", "swims": true, "tex": "entity/nautilus/nautilus", "tex_size": [128, 128], "xp": [1, 3], "spawn": "in_water", "parts": DOLPHIN},
	"zombie_nautilus": {"hp": 15, "speed": 1.0, "w": 0.875, "h": 0.95, "kind": "hostile", "swims": true, "attack": 4.0, "tex": "entity/nautilus/zombie_nautilus", "tex_size": [128, 128], "xp": [5, 5], "spawn": "in_water", "parts": DOLPHIN},
	"bat": {"hp": 6, "speed": 0.1, "w": 0.5, "h": 0.9, "kind": "passive", "flies": true, "small_flyer": true, "tex": "entity/bat/bat", "tex_size": [32, 32], "xp": [0, 0], "parts": BAT},
	"parrot": {"hp": 6, "speed": 0.2, "w": 0.5, "h": 0.9, "kind": "passive", "flies": true, "small_flyer": true, "tex": "entity/parrot/parrot_red_blue", "tex_size": [32, 32], "food": ["wheat_seeds", "melon_seeds", "pumpkin_seeds", "beetroot_seeds"], "xp": [1, 3], "parts": PARROT},
	"allay": {"hp": 20, "speed": 0.1, "w": 0.35, "h": 0.6, "kind": "passive", "flies": true, "small_flyer": true, "tex": "entity/allay/allay", "tex_size": [32, 32], "xp": [0, 0], "parts": ALLAY},
	"phantom": {"hp": 20, "speed": 0.5, "w": 0.9, "h": 0.5, "kind": "hostile", "flies": true, "small_flyer": true, "swoops": true, "burns": true, "attack": 6.0, "tex": "entity/phantom/phantom", "tex_size": [64, 64], "xp": [5, 5], "parts": PHANTOM},
	"bogged": {"hp": 16, "speed": 0.25, "w": 0.6, "h": 1.99, "kind": "hostile", "ranged": true, "burns": true, "tex": "entity/skeleton/bogged", "tex_size": [64, 32], "attack": 2.0, "xp": [5, 5], "rig": "skeleton"},
	"parched": {"hp": 16, "speed": 0.25, "w": 0.6, "h": 1.99, "kind": "hostile", "ranged": true, "tex": "entity/skeleton/parched", "tex_size": [64, 32], "attack": 2.0, "xp": [5, 5], "rig": "skeleton"},
	"breeze": {"hp": 30, "speed": 0.63, "w": 0.6, "h": 1.77, "kind": "hostile", "wind_charge": true, "tex": "entity/breeze/breeze", "tex_size": [32, 32], "xp": [10, 10], "parts": ALLAY, "scale": 2.0},
	"creaking": {"hp": 1, "speed": 0.4, "w": 0.9, "h": 2.7, "kind": "hostile", "attack": 3.0, "tex": "entity/creaking/creaking", "tex_size": [64, 64], "xp": [0, 0], "parts": CREAKING},
	"warden": {"hp": 500, "speed": 0.3, "w": 0.9, "h": 2.9, "kind": "hostile", "attack": 30.0, "tex": "entity/warden/warden", "tex_size": [128, 128], "xp": [5, 5], "parts": IRON_GOLEM},
	"copper_golem": {"hp": 12, "speed": 0.2, "w": 0.49, "h": 0.98, "kind": "passive", "golem": true, "tex": "entity/copper_golem/copper_golem", "tex_size": [64, 64], "xp": [0, 0], "parts": VEX, "scale": 1.6},
	"happy_ghast": {"hp": 20, "speed": 0.05, "w": 4.0, "h": 4.0, "kind": "passive", "flies": true, "rideable": true, "tex": "entity/ghast/happy_ghast", "tex_size": [64, 64], "scale": 4.5, "xp": [0, 0], "rig": "ghast"},
	"sulfur_cube": {"hp": 16, "speed": 0.2, "w": 2.08, "h": 2.08, "kind": "hostile", "hops": true, "splits": true, "size": 4, "tex": "entity/sulfur_cube/sulfur_cube_outer", "tex_size": [64, 32], "attack": 4.0, "xp": [4, 4], "rig": "slime"},
	"giant": {"hp": 100, "speed": 0.5, "w": 3.6, "h": 12.0, "kind": "hostile", "attack": 50.0, "tex": "entity/zombie/zombie", "tex_size": [64, 64], "scale": 6.0, "xp": [5, 5], "rig": "humanoid"},
	"wither": {"hp": 300, "speed": 0.6, "w": 0.9, "h": 3.5, "kind": "hostile", "flies": true, "boss": true, "fire_immune": true, "fireball": "wither_skull", "hover_y": 5.0, "tex": "entity/wither/wither", "tex_size": [64, 64], "scale": 2.0, "xp": [50, 50], "parts": WITHER},
}
