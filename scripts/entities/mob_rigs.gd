## MobRigs — Java entity model layer definitions (EntityModelSet LayerDefinitions, recalled; source D) transcribed
## part by part: [name, pivot, box origin, box size, texOffs, xRot deg, zRot deg, yRot deg, inflate, extra boxes].
## "nest" keeps Java's part hierarchy (child pivot / rotation relative to its parent), "hidden" parts start invisible
## (shown by state: illager crossed arms / hat), "layers" are render layers with their own texture (breeze wind).
## Checked against each texture's box-UV layout with --rigcheck (opaque share of every face, unused texels).
## Overrides the placeholder rigs of MobRegistry*.DEFS (MobRegistry.get_def).
class_name MobRigs

const R90 := 90.0
const R180 := 180.0
const RAD := 57.29577951308232   # degrees per radian (Java PartPose angles are radians)

# ---------------------------------------------------------------- humanoids

## Java HumanoidModel.createMesh (64 x 64 / 64 x 32): head + hat layer (0.5), body, arms, legs.
const HUMANOID := [["head", [0, 0, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0, 0, 0, 0.0, [["hat_layer", [-4, -8, -4], [8, 8, 8], [32, 0], 0.5]]],
	["body", [0, 0, 0], [-4, 0, -2], [8, 12, 4], [16, 16], 0],
	["arm0", [-5, 2, 0], [-3, -2, -2], [4, 12, 4], [40, 16], 0], ["arm1", [5, 2, 0], [-1, -2, -2], [4, 12, 4], [40, 16], 0],
	["leg0", [-1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 16], 0], ["leg1", [1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 16], 0]]
## Java DrownedModel: zombie layout with its own left arm (32, 48) and left leg (16, 48).
const DROWNED := [["head", [0, 0, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0, 0, 0, 0.0, [["hat_layer", [-4, -8, -4], [8, 8, 8], [32, 0], 0.5]]],
	["body", [0, 0, 0], [-4, 0, -2], [8, 12, 4], [16, 16], 0],
	["arm0", [-5, 2, 0], [-3, -2, -2], [4, 12, 4], [40, 16], 0], ["arm1", [5, 2, 0], [-1, -2, -2], [4, 12, 4], [32, 48], 0],
	["leg0", [-1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 16], 0], ["leg1", [1.9, 12, 0], [-2, 0, -2], [4, 12, 4], [16, 48], 0]]

## Java ZombieVillagerModel: villager head (10 tall) with the nose on the head part, hat layer + rim, body + robe
## (0.05), zombie arms 4 x 12 x 4 at (44, 22), legs.
const ZOMBIE_VILLAGER := [["head", [0, 0, 0], [-4, -10, -4], [8, 10, 8], [0, 0], 0, 0, 0, 0.0,
		[["nose_box", [-1, -3, -6], [2, 4, 2], [24, 0], 0.0], ["zv_hat", [-4, -10, -4], [8, 10, 8], [32, 0], 0.5]]],
	["hat_rim", [0, 0, 0], [-8, -8, -6], [16, 16, 1], [30, 47], -90],
	["body", [0, 0, 0], [-4, 0, -3], [8, 12, 6], [16, 20], 0, 0, 0, 0.0, [["robe", [-4, 0, -3], [8, 20, 6], [0, 38], 0.05]]],
	["arm0", [-5, 2, 0], [-3, -2, -2], [4, 12, 4], [44, 22], 0], ["arm1", [5, 2, 0], [-1, -2, -2], [4, 12, 4], [44, 22], 0],
	["leg0", [-2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0], ["leg1", [2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0]]
const ZOMBIE_VILLAGER_NEST := {"hat_rim": "head"}

## Java IllagerModel: head + hat (illusioner only, 8 x 12 x 8 at 0.45) + nose, body + robe (0.5), crossed arms
## (arms: 4 x 8 x 4 side + 8 x 4 x 4 middle at xRot -0.75, left shoulder), separate arms (40, 46), legs.
const ILLAGER := [["head", [0, 0, 0], [-4, -10, -4], [8, 10, 8], [0, 0], 0],
	["illager_hat", [0, 0, 0], [-4, -10, -4], [8, 12, 8], [32, 0], 0, 0, 0, 0.45],
	["nose", [0, -2, 0], [-1, -1, -6], [2, 4, 2], [24, 0], 0],
	["body", [0, 0, 0], [-4, 0, -3], [8, 12, 6], [16, 20], 0, 0, 0, 0.0, [["robe", [-4, 0, -3], [8, 20, 6], [0, 38], 0.5]]],
	["arms", [0, 3, -1], [-8, -2, -2], [4, 8, 4], [44, 22], -0.75 * RAD, 0, 0, 0.0,
		[["arms_mid", [-4, 2, -2], [8, 4, 4], [40, 38], 0.0], ["left_shoulder", [4, -2, -2], [4, 8, 4], [44, 22], 0.0]]],
	["arm0", [-5, 2, 0], [-3, -2, -2], [4, 12, 4], [40, 46], 0], ["arm1", [5, 2, 0], [-1, -2, -2], [4, 12, 4], [40, 46], 0],
	["leg0", [-2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0], ["leg1", [2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0]]
const ILLAGER_NEST := {"illager_hat": "head", "nose": "head"}

## Java WitchModel: VillagerModel with the head replaced (no hat layer), the four-tier hat (each tier relative to the
## one below, tilted), nose with the mole, robe, crossed arms, legs. Texture 64 x 128.
const WITCH := [["head", [0, 0, 0], [-4, -10, -4], [8, 10, 8], [0, 0], 0],
	["witch_hat", [-5, -10.03125, -5], [0, 0, 0], [10, 2, 10], [0, 64], 0],
	["witch_hat2", [1.75, -4, 2], [0, 0, 0], [7, 4, 7], [0, 76], -3.0, 1.5],
	["witch_hat3", [1.75, -4, 2], [0, 0, 0], [4, 4, 4], [0, 87], -6.0, 3.0],
	["witch_hat4", [1.75, -2, 2], [0, 0, 0], [1, 2, 1], [0, 95], -12.0, 6.0, 0, 0.25],
	["nose", [0, -2, 0], [-1, -1, -6], [2, 4, 2], [24, 0], 0],
	["mole", [0, -2, 0], [0, 3, -6.75], [1, 1, 1], [0, 0], 0, 0, 0, -0.25],
	["body", [0, 0, 0], [-4, 0, -3], [8, 12, 6], [16, 20], 0, 0, 0, 0.0, [["robe", [-4, 0, -3], [8, 20, 6], [0, 38], 0.5]]],
	["arms", [0, 3, -1], [-8, -2, -2], [4, 8, 4], [44, 22], -0.75 * RAD, 0, 0, 0.0,
		[["arms_mid", [-4, 2, -2], [8, 4, 4], [40, 38], 0.0], ["left_shoulder", [4, -2, -2], [4, 8, 4], [44, 22], 0.0]]],
	["leg0", [-2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0], ["leg1", [2, 12, 0], [-2, 0, -2], [4, 12, 4], [0, 22], 0]]
const WITCH_NEST := {"witch_hat": "head", "witch_hat2": "witch_hat", "witch_hat3": "witch_hat2", "witch_hat4": "witch_hat3",
	"nose": "head", "mole": "nose"}

## Java EndermanModel (64 x 32): HumanoidModel at y -14 with the jaw "hat" (0, 16) deflated 0.5, 30-long limbs.
const ENDERMAN := [["head", [0, -14, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0],
	["jaw", [0, -13, 0], [-4, -8, -4], [8, 8, 8], [0, 16], 0, 0, 0, -0.5],
	["body", [0, -14, 0], [-4, 0, -2], [8, 12, 4], [32, 16], 0],
	["arm0", [-5, -12, 0], [-1, -2, -1], [2, 30, 2], [56, 0], 0], ["arm1", [5, -12, 0], [-1, -2, -1], [2, 30, 2], [56, 0], 0],
	["leg0", [-2, -5, 0], [-1, 0, -1], [2, 30, 2], [56, 0], 0], ["leg1", [2, -5, 0], [-1, 0, -1], [2, 30, 2], [56, 0], 0]]

# ---------------------------------------------------------------- deep dark / trial chambers

## Java WardenModel (128 x 128): bone (0, 24, 0) > body (0, -21, 0) > head (0, -13, 0) > tendrils; ribcage planes and
## arms on the body; legs on the bone. Arms / head flattened to absolute pivots (body unrotated) for the animation.
const WARDEN := [["body", [0, 3, 0], [-9, -13, -4], [18, 21, 11], [0, 0], 0],
	["rib_r", [-7, -2, -4], [-2, -11, -0.1], [9, 21, 0], [90, 11], 0], ["rib_l", [7, -2, -4], [-7, -11, -0.1], [9, 21, 0], [90, 11], 0],
	["head", [0, -10, 0], [-8, -16, -5], [16, 16, 10], [0, 32], 0],
	["tendril_r", [-8, -12, 0], [-16, -13, 0], [16, 16, 0], [52, 32], 0], ["tendril_l", [8, -12, 0], [0, -13, 0], [16, 16, 0], [58, 0], 0],
	["arm0", [-13, -10, 1], [-4, 0, -4], [8, 28, 8], [44, 50], 0], ["arm1", [13, -10, 1], [-4, 0, -4], [8, 28, 8], [0, 58], 0],
	["leg0", [-5.9, 11, 0], [-3.1, 0, -3], [6, 13, 6], [76, 48], 0], ["leg1", [5.9, 11, 0], [-2.9, 0, -3], [6, 13, 6], [76, 76], 0]]
const WARDEN_NEST := {"rib_r": "body", "rib_l": "body", "tendril_r": "head", "tendril_l": "head"}

## Java BreezeModel (32 x 32): body > rods (0, 8, 0) > three rods, head (0, 4, 0) with the eye band; wind layer
## (breeze_wind.png 128 x 128): wind_bottom (0, 24) > wind_mid (0, -7) > wind_top (0, -6), three nested boxes each.
const BREEZE := [["head", [0, 4, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0, 0, 0, 0.0, [["eyes", [-5, -5, -4.2], [10, 3, 4], [4, 24], 0.0]]],
	["rods", [0, 8, 0], [0, 0, 0], [0, 0, 0], [0, 0], 0],
	["rod1", [2.5981, -3, 1.5], [-1, 0, -3], [2, 8, 2], [0, 17], -2.7489 * RAD, 3.1416 * RAD, -1.0472 * RAD],
	["rod2", [-2.5981, -3, 1.5], [-1, 0, -3], [2, 8, 2], [0, 17], -2.7489 * RAD, 3.1416 * RAD, 1.0472 * RAD],
	["rod3", [0, -3, -3], [-1, 0, -3], [2, 8, 2], [0, 17], 0.3927 * RAD]]
const BREEZE_NEST := {"rod1": "rods", "rod2": "rods", "rod3": "rods"}
const BREEZE_WIND := [["wind_bottom", [0, 24, 0], [-2.5, -7, -2.5], [5, 7, 5], [1, 83], 0],
	["wind_mid", [0, -7, 0], [-6, -6, -6], [12, 6, 12], [74, 28], 0, 0, 0, 0.0, [["wind_mid2", [-4, -6, -4], [8, 6, 8], [78, 32], 0.0], ["wind_mid3", [-2.5, -6, -2.5], [5, 6, 5], [49, 71], 0.0]]],
	["wind_top", [0, -6, 0], [-9, -8, -9], [18, 8, 18], [0, 0], 0, 0, 0, 0.0, [["wind_top2", [-6, -8, -6], [12, 8, 12], [6, 6], 0.0], ["wind_top3", [-2.5, -8, -2.5], [5, 8, 5], [105, 57], 0.0]]]]
const BREEZE_WIND_NEST := {"wind_mid": "wind_bottom", "wind_top": "wind_mid"}

# ---------------------------------------------------------------- 1.20+ passive mobs

## Java SnifferModel (192 x 192): bone (0, 5, 0) > body (fur 0.5, belly plane) > head (0, 6.5, -19.48) > ears, nose,
## lower beak; six legs on the bone.
const SNIFFER := [["body", [0, 5, 0], [-12.5, -14, -20], [25, 29, 40], [62, 68], 0, 0, 0, 0.0,
		[["fur", [-12.5, -14, -20], [25, 24, 40], [62, 0], 0.5], ["belly", [-12.5, 12, -20], [25, 0, 40], [87, 68], 0.0]]],
	["head", [0, 11.5, -19.48], [-6.5, -7.5, -11.5], [13, 18, 11], [8, 15], 0, 0, 0, 0.0, [["head_bottom", [-6.5, 7.5, -11.5], [13, 0, 11], [8, 4], 0.0]]],
	["ear_l", [6.51, -7.5, -4.51], [0, 0, -3], [1, 19, 7], [2, 0], 0], ["ear_r", [-6.51, -7.5, -4.51], [-1, 0, -3], [1, 19, 7], [48, 0], 0],
	["sniffer_nose", [0, -4.5, -11.5], [-6.5, -2, -9], [13, 2, 9], [10, 45], 0],
	["lower_beak", [0, 2.5, -12.5], [-6.5, -7, -8], [13, 12, 9], [10, 57], 0],
	["leg0", [-7.5, 15, -15], [-3.5, -1, -4], [7, 10, 8], [32, 87], 0], ["leg1", [7.5, 15, -15], [-3.5, -1, -4], [7, 10, 8], [0, 87], 0],
	["leg2", [-7.5, 15, 0], [-3.5, -1, -4], [7, 10, 8], [32, 105], 0], ["leg3", [7.5, 15, 0], [-3.5, -1, -4], [7, 10, 8], [0, 105], 0],
	["leg4", [-7.5, 15, 15], [-3.5, -1, -4], [7, 10, 8], [32, 123], 0], ["leg5", [7.5, 15, 15], [-3.5, -1, -4], [7, 10, 8], [0, 123], 0]]
const SNIFFER_NEST := {"ear_l": "head", "ear_r": "head", "sniffer_nose": "head", "lower_beak": "head"}

## Java ArmadilloModel (64 x 64): body (0, 21, 4) shell (0.3) + inner, tail, head (0, -2, -11) cube tilted -22.5,
## ears; four short legs.
const ARMADILLO := [["body", [0, 21, 4], [-4, -7, -10], [8, 8, 12], [0, 20], 0, 0, 0, 0.3, [["inner", [-4, -7, -10], [8, 8, 12], [0, 40], 0.0]]],
	["tail", [0, -3, 1], [-0.5, -0.0865, 0.0933], [1, 6, 1], [44, 53], 0.5061 * RAD],
	["head", [0, 19, -7], [0, 0, 0], [0, 0, 0], [0, 0], 0],
	["head_cube", [0, 0, 0], [-1.5, -1, -1], [3, 5, 2], [43, 15], -0.3927 * RAD],
	["ear_r", [-1.5, -1, -0.6], [-2, -3, 0], [2, 5, 0], [43, 10], 0.1886 * RAD, -0.0718 * RAD, -0.3864 * RAD],
	["ear_l", [1.5, -1, -0.6], [0, -3, 0], [2, 5, 0], [47, 10], 0.1886 * RAD, 0.0718 * RAD, 0.3864 * RAD],
	["leg0", [-2, 21, 4], [-1, 0, -1], [2, 3, 2], [51, 31], 0], ["leg1", [2, 21, 4], [-1, 0, -1], [2, 3, 2], [42, 31], 0],
	["leg2", [-2, 21, -4], [-1, 0, -1], [2, 3, 2], [51, 43], 0], ["leg3", [2, 21, -4], [-1, 0, -1], [2, 3, 2], [42, 43], 0]]
const ARMADILLO_NEST := {"tail": "body", "head_cube": "head", "ear_r": "head", "ear_l": "head"}

## Java CamelModel (128 x 128): body (0, 4, 9.5) > hump, tail, head (0, -3, -19.5) (head + neck + muzzle) > ears;
## four long legs.
const CAMEL := [["body", [0, 4, 9.5], [-7.5, -12, -23.5], [15, 12, 27], [0, 25], 0],
	["hump", [0, -12, -10], [-4.5, -5, -5.5], [9, 5, 11], [74, 0], 0], ["tail", [0, -9, 3.5], [-1.5, 0, 0], [3, 14, 0], [122, 0], 0],
	["head", [0, 1, -10], [-3.5, -7, -15], [7, 8, 19], [60, 24], 0, 0, 0, 0.0,
		[["neck", [-3.5, -21, -15], [7, 14, 7], [21, 0], 0.0], ["muzzle", [-2.5, -21, -21], [5, 5, 6], [50, 0], 0.0]]],
	["ear_l", [3, -21, -9.5], [-0.5, 0.5, -1], [3, 1, 2], [45, 0], 0], ["ear_r", [-3, -21, -9.5], [-2.5, 0.5, -1], [3, 1, 2], [67, 0], 0],
	["leg0", [-4.9, 1, 9.5], [-2.5, 2, -2.5], [5, 21, 5], [94, 16], 0], ["leg1", [4.9, 1, 9.5], [-2.5, 2, -2.5], [5, 21, 5], [58, 16], 0],
	["leg2", [-4.9, 1, -10.5], [-2.5, 2, -2.5], [5, 21, 5], [0, 26], 0], ["leg3", [4.9, 1, -10.5], [-2.5, 2, -2.5], [5, 21, 5], [0, 0], 0]]
const CAMEL_NEST := {"hump": "body", "tail": "body", "ear_l": "head", "ear_r": "head"}

## Java FrogModel (48 x 48): root (0, 24) > body (0, -2, 4) (+ belly plane) > head (0, -2, -1) (+ mouth plane) > eyes;
## arms with hand planes, legs with foot planes (flattened to absolute pivots).
const FROG := [["body", [0, 22, 4], [-3.5, -2, -8], [7, 3, 9], [3, 1], 0, 0, 0, 0.0, [["belly", [-3.5, -1, -8], [7, 0, 9], [23, 22], 0.0]]],
	["head", [0, 20, 3], [-3.5, -2, -7], [7, 3, 9], [0, 13], 0, 0, 0, 0.0, [["mouth", [-3.5, -1, -7], [7, 0, 9], [23, 13], 0.0]]],
	["eye_r", [-2, -3, -4.5], [-1.5, -1, -1.5], [3, 2, 3], [0, 0], 0], ["eye_l", [2, -3, -4.5], [-1.5, -1, -1.5], [3, 2, 3], [0, 5], 0],
	["arm1", [4, 21, -2.5], [-1, 0, -1], [2, 3, 3], [0, 32], 0, 0, 0, 0.0, [["hand_l", [-4, 3.01, -5], [8, 0, 8], [18, 40], 0.0]]],
	["arm0", [-4, 21, -2.5], [-1, 0, -1], [2, 3, 3], [0, 38], 0, 0, 0, 0.0, [["hand_r", [-4, 3.01, -5], [8, 0, 8], [2, 40], 0.0]]],
	["leg1", [3.5, 21, 4], [-1, 0, -2], [3, 3, 4], [14, 25], 0, 0, 0, 0.0, [["foot_l", [-2, 3.01, -4], [8, 0, 8], [2, 32], 0.0]]],
	["leg0", [-3.5, 21, 4], [-2, 0, -2], [3, 3, 4], [0, 25], 0, 0, 0, 0.0, [["foot_r", [-6, 3.01, -4], [8, 0, 8], [18, 32], 0.0]]]]
const FROG_NEST := {"eye_r": "head", "eye_l": "head"}

## Java BatModel (32 x 32, 1.20.3): body > wings > wing tips, feet; head > ears.
const BAT := [["head", [0, 17, 0], [-2, -3, -1], [4, 3, 2], [0, 0], 0],
	["ear_r", [-1.5, -2, -1], [-2.5, -4, 0], [3, 5, 0], [1, 15], 0], ["ear_l", [1.1, -3, -1], [-0.1, -3, 0], [3, 5, 0], [8, 15], 0],
	["body", [0, 17, 0], [-1.5, 0, -1], [3, 5, 2], [0, 7], 0],
	["wing0", [-1.5, 0, 0], [-2, -2, 0], [2, 7, 0], [12, 0], 0], ["wing_tip0", [-2, 0, 0], [-6, -2, 0], [6, 8, 0], [16, 0], 0],
	["wing1", [1.5, 0, 0], [0, -2, 0], [2, 7, 0], [12, 7], 0], ["wing_tip1", [2, 0, 0], [0, -2, 0], [6, 8, 0], [16, 8], 0],
	["feet", [0, 5, 0], [-1.5, 0, 0], [3, 2, 0], [16, 16], 0]]
const BAT_NEST := {"ear_r": "head", "ear_l": "head", "wing0": "body", "wing_tip0": "wing0", "wing1": "body", "wing_tip1": "wing1", "feet": "body"}

## Java AllayModel (32 x 32): root (0, 23.5) > head (0, -3.99), body (0, -4) (+ deflated robe) > arms, wing planes.
const ALLAY := [["head", [0, 19.51, 0], [-2.5, -5, -2.5], [5, 5, 5], [0, 0], 0],
	["body", [0, 19.5, 0], [-1.5, 0, -1], [3, 4, 2], [0, 10], 0, 0, 0, 0.0, [["robe", [-1.5, 0, -1], [3, 5, 2], [0, 16], -0.2]]],
	["arm0", [-1.75, 0.5, 0], [-0.75, -0.5, -1], [1, 4, 2], [23, 0], 0, 0, 0, -0.01],
	["arm1", [1.75, 0.5, 0], [-0.25, -0.5, -1], [1, 4, 2], [23, 6], 0, 0, 0, -0.01],
	["wing0", [-0.5, 0, 0.6], [0, 1, 0], [0, 5, 8], [16, 14], 0], ["wing1", [0.5, 0, 0.6], [0, 1, 0], [0, 5, 8], [16, 14], 0]]
const ALLAY_NEST := {"wing0": "body", "wing1": "body", "arm0": "body", "arm1": "body"}   # (arms: body children, pivots relative)

## Java VexModel (32 x 32): root (0, -2.5) > head (0, 20), body (0, 20) (+ robe) > arms, wing planes.
const VEX := [["head", [0, 17.5, 0], [-2.5, -5, -2.5], [5, 5, 5], [0, 0], 0],
	["body", [0, 17.5, 0], [-1.5, 0, -1], [3, 4, 2], [0, 10], 0, 0, 0, 0.0, [["robe", [-1.5, 1, -1], [3, 5, 2], [0, 16], -0.2]]],
	["arm0", [-1.75, 17.75, 0], [-1.25, -0.5, -1], [2, 4, 2], [23, 0], 0, 0, 0, -0.1],
	["arm1", [1.75, 17.75, 0], [-0.75, -0.5, -1], [2, 4, 2], [23, 6], 0, 0, 0, -0.1],
	["wing1", [0.5, 1, 1], [0, 0, 0], [0, 5, 8], [16, 14], 0], ["wing0", [-0.5, 1, 1], [0, 0, 0], [0, 5, 8], [16, 14], 0]]
const VEX_NEST := {"wing0": "body", "wing1": "body"}

## Java GuardianModel (64 x 64): head (body + sides + top / bottom), 12 spikes (positions from setupAnim with the
## spikes out), eye on the front, three tail segments.
static func guardian_parts() -> Array:
	var parts: Array = [["head", [0, 0, 0], [-6, 10, -8], [12, 12, 16], [0, 0], 0, 0, 0, 0.0,
		[["side_r", [-8, 10, -6], [2, 12, 12], [0, 28], 0.0], ["side_l", [6, 10, -6], [2, 12, 12], [0, 28], 0.0],
		["top", [-6, 8, -6], [12, 2, 12], [16, 40], 0.0], ["bottom", [-6, 22, -6], [12, 2, 12], [16, 40], 0.0]]]]
	var xr := [1.75, 0.25, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 1.25, 0.75, 0.0, 0.0]
	var yr := [0.0, 0.0, 0.0, 0.0, 0.25, 1.75, 1.25, 0.75, 0.0, 0.0, 0.0, 0.0]
	var zr := [0.0, 0.0, 0.25, 1.75, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.75, 1.25]
	var sx := [0.0, 0.0, 8.0, -8.0, -8.0, 8.0, 8.0, -8.0, 0.0, 0.0, 8.0, -8.0]
	var sy := [-8.0, -8.0, -8.0, -8.0, 0.0, 0.0, 0.0, 0.0, 8.0, 8.0, 8.0, 8.0]
	var sz := [8.0, -8.0, 0.0, 0.0, -8.0, -8.0, 8.0, 8.0, 8.0, -8.0, 0.0, 0.0]
	for i in 12:
		parts.append(["spike%d" % i, [sx[i], 16.0 + sy[i], sz[i]], [-1, -4.5, -1], [2, 9, 2], [0, 0], xr[i] * 180.0, zr[i] * 180.0, yr[i] * 180.0])
	parts.append(["eye", [0, 0, -8.25], [-1, 15, 0], [2, 2, 1], [8, 0], 0])
	parts.append(["tail0", [0, 0, 0], [-2, 14, 7], [4, 4, 8], [40, 0], 0])
	parts.append(["tail1", [-1.5, 0.5, 14], [0, 14, 0], [3, 3, 7], [0, 54], 0])
	parts.append(["tail2", [0.5, 0.5, 6], [0, 14, 0], [2, 2, 6], [41, 32], 0, 0, 0, 0.0, [["tail_fin", [1, 10.5, 3], [1, 9, 9], [25, 19], 0.0]]])
	return parts
const GUARDIAN_NEST := {"tail1": "tail0", "tail2": "tail1"}

## Java GoatModel (64 x 64): head (1, 14, 0) with ears / goatee boxes, horns, nose (head box) tilted 55; legs; body
## (main + chest fur).
const GOAT := [["head", [1, 14, 0], [-6, -11, -10], [3, 2, 1], [2, 61], 0, 0, 0, 0.0,
		[["ear_l", [2, -11, -10], [3, 2, 1], [2, 61], 0.0], ["goatee", [-0.5, -3, -14], [0, 7, 5], [23, 52], 0.0]]],
	["horn_l", [0, 0, 0], [-0.01, -16, -10], [2, 7, 2], [12, 55], 0], ["horn_r", [0, 0, 0], [-2.99, -16, -10], [2, 7, 2], [12, 55], 0],
	["goat_nose", [-1, -8, -8], [-3, -4, -8], [5, 7, 10], [34, 46], 0.9599 * RAD],
	["leg0", [-3, 14, 4], [0, 4, 0], [3, 6, 3], [49, 29], 0], ["leg1", [1, 14, 4], [0, 4, 0], [3, 6, 3], [36, 29], 0],
	["leg2", [-3, 14, -6], [0, 0, 0], [3, 10, 3], [35, 2], 0], ["leg3", [1, 14, -6], [0, 0, 0], [3, 10, 3], [49, 2], 0],
	["body", [0, 24, 0], [-4, -17, -7], [9, 11, 16], [1, 1], 0, 0, 0, 0.0, [["chest", [-5, -18, -8], [11, 14, 11], [0, 28], 0.0]]]]
const GOAT_NEST := {"horn_l": "head", "horn_r": "head", "goat_nose": "head"}

## Java ParrotModel (32 x 32).
const PARROT := [["body", [0, 16.5, -3], [-1.5, 0, -1.5], [3, 6, 3], [2, 8], 0.4937 * RAD],
	["tail", [0, 21.07, 1.16], [-1.5, -1, -1], [3, 4, 1], [22, 1], 1.015 * RAD],
	["wing1", [1.5, 16.94, -2.76], [-0.5, 0, -1.5], [1, 5, 3], [19, 8], -0.6981 * RAD, 0, -R180],
	["wing0", [-1.5, 16.94, -2.76], [-0.5, 0, -1.5], [1, 5, 3], [19, 8], -0.6981 * RAD, 0, -R180],
	["head", [0, 15.69, -2.76], [-1, -1.5, -1], [2, 3, 2], [2, 2], 0],
	["head2", [0, -2, -1], [-1, -0.5, -2], [2, 1, 4], [10, 0], 0], ["beak1", [0, -0.5, -1.5], [-0.5, -1, -0.5], [1, 2, 1], [11, 7], 0],
	["beak2", [0, -1.75, -2.45], [-0.5, 0, -0.5], [1, 2, 1], [16, 7], 0],
	["feather", [0, -2.15, 0.15], [0, -4, -2], [0, 5, 4], [2, 18], -0.2214 * RAD],
	["leg1", [1, 22, -1.05], [-0.5, 0, -0.5], [1, 2, 1], [14, 18], 0], ["leg0", [-1, 22, -1.05], [-0.5, 0, -0.5], [1, 2, 1], [14, 18], 0]]
const PARROT_NEST := {"head2": "head", "beak1": "head", "beak2": "head", "feather": "head"}

## Java RabbitModel (64 x 32, the pre-1.21.x layout).
const RABBIT := [["foot_l", [3, 17.5, 3.7], [-1, 5.5, -3.7], [2, 1, 7], [26, 24], 0], ["foot_r", [-3, 17.5, 3.7], [-1, 5.5, -3.7], [2, 1, 7], [8, 24], 0],
	["leg1", [3, 17.5, 3.7], [-1, 0, 0], [2, 4, 5], [30, 15], -20], ["leg0", [-3, 17.5, 3.7], [-1, 0, 0], [2, 4, 5], [16, 15], -20],
	["body", [0, 19, 8], [-3, -2, -10], [6, 5, 10], [0, 0], -20],
	["leg3", [3, 17, -1], [-1, 0, -1], [2, 7, 2], [8, 15], -10], ["leg2", [-3, 17, -1], [-1, 0, -1], [2, 7, 2], [0, 15], -10],
	["head", [0, 16, -1], [-2.5, -4, -5], [5, 4, 5], [32, 0], 0, 0, 0, 0.0, [["rabbit_nose", [-0.5, -2.5, -5.5], [1, 1, 1], [32, 9], 0.0]]],
	["ear_r", [0, 0, 0], [-2.5, -9, -1], [2, 5, 1], [52, 0], 0, 0, -15], ["ear_l", [0, 0, 0], [0.5, -9, -1], [2, 5, 1], [58, 0], 0, 0, 15],
	["tail", [0, 20, 7], [-1.5, -1.5, 0], [3, 3, 2], [52, 6], -20]]
const RABBIT_NEST := {"ear_r": "head", "ear_l": "head"}

## Java LavaSlimeModel (64 x 32): eight 8 x 1 x 8 segments (texOffs 0, i except 24, 10 / 24, 19) + 4^3 core.
static func magma_parts() -> Array:
	var parts: Array = []
	for i in 8:
		var uv := [0, i]
		if i == 2:
			uv = [24, 10]
		elif i == 3:
			uv = [24, 19]
		parts.append(["cube%d" % i, [0, 0, 0], [-4, 16 + i, -4], [8, 1, 8], uv, 0])
	parts.append(["core", [0, 0, 0], [-2, 18, -2], [4, 4, 4], [0, 16], 0])
	return parts

## Java SilverfishModel (64 x 32): seven body segments + three fur layers.
static func silverfish_parts() -> Array:
	var sizes := [[3, 2, 2], [4, 3, 2], [6, 4, 3], [3, 3, 3], [2, 2, 3], [2, 1, 2], [1, 1, 2]]
	var texs := [[0, 0], [0, 4], [0, 9], [0, 16], [0, 22], [11, 0], [13, 4]]
	var parts: Array = []
	var f := -3.5
	var place: Array = []
	for i in sizes.size():
		var s: Array = sizes[i]
		parts.append(["segment%d" % i, [0, 24 - s[1], f], [s[0] * -0.5, 0, s[2] * -0.5], s, texs[i], 0])
		place.append(f)
		if i < sizes.size() - 1:
			f += (s[2] + sizes[i + 1][2]) * 0.5
	parts.append(["layer0", [0, 16, place[2]], [-5, 0, sizes[2][2] * -0.5], [10, 8, sizes[2][2]], [20, 0], 0])
	parts.append(["layer1", [0, 20, place[4]], [-3, 0, sizes[4][2] * -0.5], [6, 4, sizes[4][2]], [20, 11], 0])
	parts.append(["layer2", [0, 19, place[1]], [-3, 0, sizes[4][2] * -0.5], [6, 5, sizes[1][2]], [20, 18], 0])
	return parts

## Java CodModel (32 x 32).
const COD := [["body", [0, 22, 0], [-1, -2, 0], [2, 4, 7], [0, 0], 0], ["head", [0, 22, 0], [-1, -2, -3], [2, 4, 3], [11, 0], 0],
	["nose", [0, 22, -3], [-1, -2, -1], [2, 3, 1], [0, 0], 0],
	["fin_r", [-1, 23, 0], [-2, 0, -1], [2, 0, 2], [22, 1], 0, -45], ["fin_l", [1, 23, 0], [0, 0, -1], [2, 0, 2], [22, 4], 0, 45],
	["tail", [0, 22, 7], [0, -2, 0], [0, 4, 4], [22, 3], 0], ["top_fin", [0, 20, 0], [0, -1, -1], [0, 1, 6], [20, -6], 0]]
## Java SalmonModel (32 x 32).
const SALMON := [["body_front", [0, 20, 0], [-1.5, -2.5, 0], [3, 5, 8], [0, 0], 0], ["tail", [0, 20, 8], [-1.5, -2.5, 0], [3, 5, 8], [0, 13], 0],
	["head", [0, 20, 0], [-1, -2, -3], [2, 4, 3], [22, 0], 0],
	["back_fin", [0, 0, 8], [0, -2.5, 0], [0, 5, 6], [20, 10], 0],
	["top_front_fin", [0, -4.5, 5], [0, 0, 0], [0, 2, 3], [2, 1], 0], ["top_back_fin", [0, -4.5, -1], [0, 0, 0], [0, 2, 4], [0, 2], 0],
	["fin_r", [-1.5, 21.5, 0], [-2, 0, 0], [2, 0, 2], [-4, 0], 0, -45], ["fin_l", [1.5, 21.5, 0], [0, 0, 0], [2, 0, 2], [0, 0], 0, 45]]
const SALMON_NEST := {"back_fin": "tail", "top_front_fin": "body_front", "top_back_fin": "tail"}
## Java PufferfishSmallModel (32 x 32): the deflated fish.
const PUFFERFISH := [["body", [0, 23, 0], [-1.5, -2, -1.5], [3, 2, 3], [0, 27], 0],
	["eye_r", [0, 20, 0], [-1.5, 0, -1.5], [1, 1, 1], [24, 6], 0], ["eye_l", [0, 20, 0], [0.5, 0, -1.5], [1, 1, 1], [28, 6], 0],
	["back_fin", [0, 22, 1.5], [-1.5, 0, 0], [3, 0, 3], [-3, 0], 0],
	["fin_r", [-1.5, 22, -1.5], [-1, 0, 0], [1, 0, 2], [25, 0], 0], ["fin_l", [1.5, 22, -1.5], [0, 0, 0], [1, 0, 2], [25, 0], 0]]
## Java TropicalFishModelA (32 x 32): small fish shape.
const TROPICAL_A := [["body", [0, 22, 0], [-1, -1.5, -3], [2, 3, 6], [0, 0], 0], ["tail", [0, 22, 3], [0, -1.5, 0], [0, 3, 6], [22, -6], 0],
	["fin_r", [-1, 22.5, 0], [-2, -1, 0], [2, 2, 0], [2, 16], 0, 0, 45], ["fin_l", [1, 22.5, 0], [0, -1, 0], [2, 2, 0], [2, 12], 0, 0, -45],
	["top_fin", [0, 20.5, -3], [0, -3, 0], [0, 3, 6], [10, -5], 0]]

## Java TurtleModel (128 x 64): head, shell + belly (rotated 90), legs / flippers.
const TURTLE := [["head", [0, 19, -10], [-3, -1, -3], [6, 5, 6], [3, 0], 0],
	["body", [0, 11, -10], [-9.5, 3, -10], [19, 20, 6], [7, 37], R90, 0, 0, 0.0, [["belly", [-5.5, 3, -13], [11, 18, 3], [31, 1], 0.0]]],
	["leg0", [-3.5, 22, 11], [-2, 0, 0], [4, 1, 10], [1, 23], 0], ["leg1", [3.5, 22, 11], [-2, 0, 0], [4, 1, 10], [1, 12], 0],
	["leg2", [-5, 21, -4], [-13, 0, -2], [13, 1, 5], [27, 30], 0], ["leg3", [5, 21, -4], [0, 0, -2], [13, 1, 5], [27, 24], 0]]

## Java RavagerModel (128 x 128): neck > head (+ snout) > horns, mouth; body (2 boxes, rotated 90); legs.
const RAVAGER := [["neck", [0, -7, 5.5], [-5, -1, -18], [10, 10, 18], [68, 73], 0],
	["head", [0, 9, -11.5], [-8, -20, -14], [16, 20, 16], [0, 0], 0, 0, 0, 0.0, [["snout", [-2, -6, -18], [4, 8, 4], [0, 0], 0.0]]],
	["horn_r", [-10, -14, -8], [0, -14, -2], [2, 14, 4], [74, 55], 1.0995574 * RAD], ["horn_l", [8, -14, -8], [0, -14, -2], [2, 14, 4], [74, 55], 1.0995574 * RAD],
	["mouth", [0, -2, 2], [-8, 0, -16], [16, 3, 16], [0, 36], 0],
	["body", [0, 1, 2], [-7, -10, -7], [14, 16, 20], [0, 55], R90, 0, 0, 0.0, [["body2", [-6, 6, -7], [12, 13, 18], [0, 91], 0.0]]],
	["leg0", [-8, -13, 18], [-4, 0, -4], [8, 37, 8], [96, 0], 0], ["leg1", [8, -13, 18], [-4, 0, -4], [8, 37, 8], [96, 0], 0],
	["leg2", [-8, -13, -5], [-4, 0, -4], [8, 37, 8], [64, 0], 0], ["leg3", [8, -13, -5], [-4, 0, -4], [8, 37, 8], [64, 0], 0]]
const RAVAGER_NEST := {"horn_r": "head", "horn_l": "head", "mouth": "head"}

## Java WitherBossModel (64 x 64): shoulders, ribcage (spine + three rib bars, tilted), tail, three heads.
const WITHER := [["shoulders", [0, 0, 0], [-10, 3.9, -0.5], [20, 3, 3], [0, 16], 0],
	["ribcage", [-2, 6.9, -0.5], [0, 0, 0], [3, 10, 3], [0, 22], 0.20420352 * RAD, 0, 0, 0.0,
		[["rib0", [-4, 1.5, 0.5], [11, 2, 2], [24, 22], 0.0], ["rib1", [-4, 4, 0.5], [11, 2, 2], [24, 22], 0.0], ["rib2", [-4, 6.5, 0.5], [11, 2, 2], [24, 22], 0.0]]],
	["tail", [-2, 16.69, 1.53], [0, 0, 0], [3, 6, 3], [12, 22], 0.83252203 * RAD],
	["head", [0, 0, 0], [-4, -4, -4], [8, 8, 8], [0, 0], 0],
	["head1", [-8, 4, 0], [-4, -4, -4], [6, 6, 6], [32, 0], 0], ["head2", [10, 4, 0], [-4, -4, -4], [6, 6, 6], [32, 0], 0]]

## Java PolarBearModel (128 x 64).
const POLAR_BEAR := [["head", [0, 10, -16], [-3.5, -3, -3], [7, 7, 7], [0, 0], 0, 0, 0, 0.0,
		[["mouth", [-2.5, 1, -6], [5, 3, 3], [0, 44], 0.0], ["ear_r", [-4.5, -4, -1], [2, 2, 1], [26, 0], 0.0], ["ear_l", [2.5, -4, -1], [2, 2, 1], [26, 0], 0.0]]],
	["body", [-2, 9, 12], [-5, -13, -7], [14, 14, 11], [0, 19], R90, 0, 0, 0.0, [["back", [-4, -25, -7], [12, 12, 10], [39, 0], 0.0]]],
	["leg0", [-4.5, 14, 6], [-2, 0, -2], [4, 10, 8], [50, 22], 0], ["leg1", [4.5, 14, 6], [-2, 0, -2], [4, 10, 8], [50, 22], 0],
	["leg2", [-3.5, 14, -8], [-2, 0, -2], [4, 10, 6], [50, 40], 0], ["leg3", [3.5, 14, -8], [-2, 0, -2], [4, 10, 6], [50, 40], 0]]

## Java LlamaModel (128 x 64): head (+ neck + ears), body rotated 90, legs (chests hidden).
const LLAMA := [["head", [0, 7, -6], [-2, -14, -10], [4, 4, 9], [0, 0], 0, 0, 0, 0.0,
		[["neck", [-4, -16, -6], [8, 18, 6], [0, 14], 0.0], ["ear_r", [-4, -19, -4], [3, 3, 2], [17, 0], 0.0], ["ear_l", [1, -19, -4], [3, 3, 2], [17, 0], 0.0]]],
	["body", [0, 5, 2], [-6, -10, -7], [12, 18, 10], [29, 0], R90],
	["leg0", [-3.5, 10, 6], [-2, 0, -2], [4, 14, 4], [29, 29], 0], ["leg1", [3.5, 10, 6], [-2, 0, -2], [4, 14, 4], [29, 29], 0],
	["leg2", [-3.5, 10, -5], [-2, 0, -2], [4, 14, 4], [29, 29], 0], ["leg3", [3.5, 10, -5], [-2, 0, -2], [4, 14, 4], [29, 29], 0]]

## Java PhantomModel (64 x 64): body tilted -0.1 rad > tail base > tail tip, wing bases > wing tips (z 0.1 rad), head.
const PHANTOM := [["body", [0, 0, 0], [-3, -2, -8], [5, 3, 9], [0, 8], -0.1 * RAD],
	["tail_base", [0, -2, 1], [-2, 0, 0], [3, 2, 6], [3, 20], 0], ["tail_tip", [0, 0.5, 6], [-1, 0, 0], [1, 1, 6], [4, 29], 0],
	["wing1", [2, -2, -8], [0, 0, 0], [6, 2, 9], [23, 12], 0, 0.1 * RAD], ["wing_tip1", [6, 0, 0], [0, 0, 0], [13, 1, 9], [16, 24], 0, 0.1 * RAD],
	["wing0", [-3, -2, -8], [-6, 0, 0], [6, 2, 9], [23, 12], 0, -0.1 * RAD], ["wing_tip0", [-6, 0, 0], [-13, 0, 0], [13, 1, 9], [16, 24], 0, -0.1 * RAD],
	["head", [0, 1, -7], [-4, -2, -5], [7, 3, 5], [0, 0], 0.2 * RAD]]
const PHANTOM_NEST := {"tail_base": "body", "tail_tip": "tail_base", "wing1": "body", "wing_tip1": "wing1", "wing0": "body", "wing_tip0": "wing0", "head": "body"}

# ---------------------------------------------------------------- 26.x mobs (layouts read from the 26.3 textures)

## Java CopperGolemModel (64 x 64; every box matches the texture's box-UV layout): body (0, 19) > head (0, -6) with
## nose / antenna rod / antenna cube, arms (-+4, -6); legs on the root. Head / arms flattened to absolute pivots.
const COPPER_GOLEM := [["body", [0, 19, 0], [-4, -6, -3], [8, 6, 6], [0, 15], 0],
	["head", [0, 13, 0], [-4, -5, -5], [8, 5, 10], [0, 0], 0, 0, 0, 0.015,
		[["golem_nose", [-1, -2, -6], [2, 3, 2], [56, 0], 0.0], ["rod", [-1, -9, -1], [2, 4, 2], [37, 8], -0.015], ["rod_top", [-2, -13, -2], [4, 4, 4], [37, 0], -0.015]]],
	["arm0", [-4, 13, 0], [-3, -1, -2], [3, 10, 4], [36, 16], 0], ["arm1", [4, 13, 0], [0, -1, -2], [3, 10, 4], [50, 16], 0],
	["leg0", [0, 19, 0], [-4, 0, -2], [4, 5, 4], [0, 27], 0], ["leg1", [0, 19, 0], [0, 0, -2], [4, 5, 4], [16, 27], 0]]

## 26.x LavaSlimeModel (64 x 64 texture): eight 8 x 1 x 8 segments at (0 | 32, 0 / 9 / 18 / 27), core 4^3 at (24, 40).
static func magma_parts_263() -> Array:
	var parts: Array = []
	for i in 8:
		parts.append(["cube%d" % i, [0, 0, 0], [-4, 16 + i, -4], [8, 1, 8], [0 if i < 4 else 32, (i % 4) * 9], 0])
	parts.append(["core", [0, 0, 0], [-2, 18, -2], [4, 4, 4], [24, 40], 0])
	return parts

## 26.3 sulfur cube (128 x 128 textures): an 18^3 outer cube with the face (sulfur_cube_outer) around a 16^3 inner cube
## (sulfur_cube_inner, texOffs 0, 36). Scaled so size n spans 8 n px like a slime (hitbox 0.52 n).
const SULFUR_OUTER := [["outer", [0, 24, 0], [-9, -18, -9], [18, 18, 18], [0, 0], 0]]
const SULFUR_INNER := [["inner", [0, 24, 0], [-8, -17, -8], [16, 16, 16], [0, 36], 0]]

## 26.3 rabbit (64 x 64 texture, regions read from it): body 8 x 6 x 10, head 5^3 with 1 x 4 x 2 ears, fluffy 4^3 tail,
## front legs 2 x 4 x 2, long hind feet 2 x 1 x 6.
const RABBIT_263 := [["body", [0, 22, 3], [-4, -6, -5], [8, 6, 10], [0, 0], 0],
	["head", [0, 18, -2], [-2.5, -4, -5], [5, 5, 5], [0, 16], 0],
	["ear_r", [-1.5, -4, -2.5], [-0.5, -4, -1], [1, 4, 2], [26, 0], 0, -8], ["ear_l", [1.5, -4, -2.5], [-0.5, -4, -1], [1, 4, 2], [32, 0], 0, 8],
	["tail", [0, 17, 8], [-2, -2, 0], [4, 4, 4], [20, 16], 0],
	["leg2", [-2, 20, -1], [-1, 0, -1], [2, 4, 2], [36, 18], 0], ["leg3", [2, 20, -1], [-1, 0, -1], [2, 4, 2], [44, 18], 0],
	["leg0", [-3, 23, 6], [-1, 0, -3], [2, 1, 6], [20, 24], 0], ["leg1", [3, 23, 6], [-1, 0, -3], [2, 1, 6], [36, 24], 0]]
const RABBIT_263_NEST := {"ear_r": "head", "ear_l": "head"}

## 26.3 parched (64 x 64): the skeleton (upper half) with wraps from the lower half: head wrap 8^3 at (0, 32), body wrap
## 8 x 12 x 4 at (0, 48).
const PARCHED := [["head", [0, 0, 0], [-4, -8, -4], [8, 8, 8], [0, 0], 0, 0, 0, 0.0, [["head_wrap", [-4, -8, -4], [8, 8, 8], [0, 32], 0.3]]],
	["body", [0, 0, 0], [-4, 0, -2], [8, 12, 4], [16, 16], 0, 0, 0, 0.0, [["body_wrap", [-4, 0, -2], [8, 12, 4], [0, 48], 0.25]]],
	["arm0", [-5, 2, 0], [-1, -2, -1], [2, 12, 2], [40, 16], 0], ["arm1", [5, 2, 0], [-1, -2, -1], [2, 12, 2], [40, 16], 0],
	["leg0", [-2, 12, 0], [-1, 0, -1], [2, 12, 2], [0, 16], 0], ["leg1", [2, 12, 0], [-1, 0, -1], [2, 12, 2], [0, 16], 0]]

## 26.x nautilus (128 x 128, reconstructed from the texture's regions; APPROXIMATE geometry): striped shell 14 x 10 x 16,
## the shell's coiled front (14 x 20 plane), aperture rim 26 x 2 x 6, body 10 x 6 x 6 with two eye cubes, tentacle
## planes below the opening.
const NAUTILUS := [["body", [0, 15, 0], [-7, -10, -6], [14, 10, 16], [0, 0], 0, 0, 0, 0.0,
		[["coil", [-7, -10, -6.01], [14, 20, 0], [34, 26], 0.0], ["rim", [-13, 0, -9], [26, 2, 6], [0, 46], 0.0]]],
	["head", [0, 19, -6], [-5, -3, -6], [10, 6, 6], [14, 57], 0, 0, 0, 0.0,
		[["eye_r", [-6, -5, -4], [3, 3, 3], [4, 68], 0.0], ["eye_l", [3, -5, -4], [3, 3, 3], [25, 68], 0.0]]],
	["tent0", [-3, 22, -9], [-6, 0, 0], [12, 12, 0], [54, 54], 70], ["tent1", [3, 22, -9], [-6, 0, 0], [12, 12, 0], [54, 54], 70]]

## Java AxolotlModel (64 x 64): body (+ dorsal fin plane) > head > three gill planes, four leg planes, tail plane.
const AXOLOTL := [["body", [0, 20, 5], [-4, -2, -9], [8, 4, 10], [0, 11], 0, 0, 0, 0.0, [["fin", [0, -3, -8], [0, 5, 9], [2, 17], 0.0]]],
	["head", [0, 20, -4], [-4, -3, -5], [8, 5, 5], [0, 1], 0, 0, 0, 0.001],
	["gills_top", [0, -3, -1], [-4, -3, 0], [8, 3, 0], [3, 37], 0], ["gills_l", [-4, 0, -1], [-3, -5, 0], [3, 7, 0], [0, 40], 0],
	["gills_r", [4, 0, -1], [0, -5, 0], [3, 7, 0], [11, 40], 0],
	["leg0", [-3.5, 21, 4], [-2, 0, 0], [3, 5, 0], [2, 13], 0], ["leg1", [3.5, 21, 4], [-1, 0, 0], [3, 5, 0], [2, 13], 0],
	["leg2", [-3.5, 21, -3], [-2, 0, 0], [3, 5, 0], [2, 13], 0], ["leg3", [3.5, 21, -3], [-1, 0, 0], [3, 5, 0], [2, 13], 0],
	["tail", [0, 20, 6], [0, -3, 0], [0, 5, 12], [2, 19], 0]]
const AXOLOTL_NEST := {"gills_top": "head", "gills_l": "head", "gills_r": "head"}

## Java MushroomCowMushroomLayer: three mushroom block models (two on the back from the model root, one on the head).
const MOOSHROOM_BLOCKS := [{"parent": "", "ops": [["t", 0.2, -0.35, 0.5], ["ry", -48.0], ["s", -1, -1, 1], ["t", -0.5, -0.5, -0.5]]},
	{"parent": "", "ops": [["t", 0.2, -0.35, 0.5], ["ry", 42.0], ["t", 0.1, 0.0, -0.6], ["ry", -48.0], ["s", -1, -1, 1], ["t", -0.5, -0.5, -0.5]]},
	{"parent": "head", "ops": [["t", 0.0, -0.7, -0.2], ["ry", -78.0], ["s", -1, -1, 1], ["t", -0.5, -0.5, -0.5]]}]
## Java SnowGolemHeadLayer: the carved pumpkin on the head.
const SNOW_GOLEM_PUMPKIN := [{"parent": "head", "state": "carved_pumpkin", "ops": [["t", 0.0, -0.34375, 0.0], ["ry", 180.0], ["s", 0.625, -0.625, -0.625], ["t", -0.5, -0.5, -0.5]]}]


## id -> overrides for MobRegistry.get_def (parts, nest, hidden, layers; scale 1 unless stated).
static func rig(id: String) -> Dictionary:
	match id:
		"zombie", "husk", "giant":
			return {"parts": HUMANOID}
		"drowned":
			return {"parts": DROWNED}
		"zombie_villager":
			return {"parts": ZOMBIE_VILLAGER, "nest": ZOMBIE_VILLAGER_NEST}
		"pillager", "vindicator", "evoker":
			return {"parts": ILLAGER, "nest": ILLAGER_NEST, "hidden": ["illager_hat"], "illager": true}
		"illusioner":
			return {"parts": ILLAGER, "nest": ILLAGER_NEST, "illager": true}
		"witch":
			return {"parts": WITCH, "nest": WITCH_NEST}
		"enderman":
			return {"parts": ENDERMAN}
		"warden":
			return {"parts": WARDEN, "nest": WARDEN_NEST}
		"breeze":
			return {"parts": BREEZE, "nest": BREEZE_NEST, "layers": [{"tex": "entity/breeze/breeze_wind", "tex_size": [128, 128], "parts": BREEZE_WIND, "nest": BREEZE_WIND_NEST}]}
		"sniffer":
			return {"parts": SNIFFER, "nest": SNIFFER_NEST, "tex_size": [192, 192]}
		"armadillo":
			return {"parts": ARMADILLO, "nest": ARMADILLO_NEST}
		"camel", "camel_husk":
			return {"parts": CAMEL, "nest": CAMEL_NEST}
		"frog":
			return {"parts": FROG, "nest": FROG_NEST}
		"bat":
			return {"parts": BAT, "nest": BAT_NEST}
		"allay":
			return {"parts": ALLAY, "nest": ALLAY_NEST}
		"vex":
			return {"parts": VEX, "nest": VEX_NEST}
		"guardian", "elder_guardian":
			return {"parts": guardian_parts(), "nest": GUARDIAN_NEST}
		"goat":
			return {"parts": GOAT, "nest": GOAT_NEST}
		"parrot":
			return {"parts": PARROT, "nest": PARROT_NEST}
		"rabbit":
			return {"parts": RABBIT_263, "nest": RABBIT_263_NEST, "tex_size": [64, 64]}
		"magma_cube":
			return {"parts": magma_parts_263(), "tex_size": [64, 64]}
		"copper_golem":
			return {"parts": COPPER_GOLEM}
		"sulfur_cube":
			return {"parts": SULFUR_OUTER, "tex_size": [128, 128], "scale": 0.4444, "layers": [{"tex": "entity/sulfur_cube/sulfur_cube_inner", "tex_size": [128, 128], "parts": SULFUR_INNER}]}
		"parched":
			return {"parts": PARCHED, "tex_size": [64, 64]}
		"nautilus", "zombie_nautilus":
			return {"parts": NAUTILUS}
		"silverfish":
			return {"parts": silverfish_parts()}
		"cod":
			return {"parts": COD}
		"salmon":
			return {"parts": SALMON, "nest": SALMON_NEST}
		"pufferfish":
			return {"parts": PUFFERFISH}
		"tropical_fish":
			return {"parts": TROPICAL_A}
		"turtle":
			return {"parts": TURTLE}
		"ravager":
			return {"parts": RAVAGER, "nest": RAVAGER_NEST}
		"wither":
			return {"parts": WITHER}
		"polar_bear":
			return {"parts": POLAR_BEAR}
		"axolotl":
			return {"parts": AXOLOTL, "nest": AXOLOTL_NEST}
		"snow_golem":
			return {"block_layers": SNOW_GOLEM_PUMPKIN}
		"llama", "trader_llama":
			return {"parts": LLAMA}
		"phantom":
			return {"parts": PHANTOM, "nest": PHANTOM_NEST}
		"ender_dragon":
			return {"parts": dragon_parts(), "nest": DRAGON_NEST, "children": {}}
		"end_crystal":
			return {"parts": CRYSTAL}
	return {}


## Java EnderDragonModel layer: head (upper lip, upper head, scales and nostrils, the -x pair mirrored) with the jaw, 5
## neck and 12 tail segments (box + spine scale), the body with 3 back scales, wings with tips (left ones mirrored),
## legs with tips and feet. Body, wings and legs hang off a 	orso pivot at model (0, 16, 0): Java rolls them
## together about that point (renderToBuffer). Neck / head / tail / torso / legs are posed per frame from the flight
## history (EntityManager._dragon_pose); every part's pivot here is its rest offset.
const DRAGON_NEST := {"jaw": "head", "body": "torso", "left_wing": "torso", "left_wing_tip": "left_wing",
	"right_wing": "torso", "right_wing_tip": "right_wing", "left_front_leg": "torso", "left_front_leg_tip": "left_front_leg",
	"left_front_foot": "left_front_leg_tip", "right_front_leg": "torso", "right_front_leg_tip": "right_front_leg",
	"right_front_foot": "right_front_leg_tip", "left_hind_leg": "torso", "left_hind_leg_tip": "left_hind_leg",
	"left_hind_foot": "left_hind_leg_tip", "right_hind_leg": "torso", "right_hind_leg_tip": "right_hind_leg",
	"right_hind_foot": "right_hind_leg_tip"}


static func dragon_parts() -> Array:
	var parts: Array = [["torso", [0, 16, 0], [0, 0, 0], [0, 0, 0], [0, 0], 0]]
	parts.append(["body", [0, -12, 8], [-12, 0, -16], [24, 24, 64], [0, 0], 0, 0, 0, 0.0,
		[["scale_a", [-1, -6, -10], [2, 6, 12], [220, 53], 0.0], ["scale_b", [-1, -6, 10], [2, 6, 12], [220, 53], 0.0],
		["scale_c", [-1, -6, 30], [2, 6, 12], [220, 53], 0.0]]])
	var seg_scale := [["spine", [-1, -9, -3], [2, 4, 6], [48, 0], 0.0]]
	for i in 5:
		parts.append(["neck%d" % i, [0, 20 - 0 * i, -12 - 10 * i], [-5, -5, -5], [10, 10, 10], [192, 104], 0, 0, 0, 0.0, seg_scale])
	for j in 12:
		parts.append(["tail%d" % j, [0, 10, 60 + 10 * j], [-5, -5, -5], [10, 10, 10], [192, 104], 0, 0, 0, 0.0, seg_scale])
	parts.append(["head", [0, 20, -62], [-8, -8, -10], [16, 16, 16], [112, 30], 0, 0, 0, 0.0,
		[["upperlip", [-6, -1, -24], [12, 5, 16], [176, 44], 0.0], ["scale_l", [-5, -12, -4], [2, 4, 6], [0, 0], 0.0, true],
		["nostril_l", [-5, -3, -22], [2, 2, 4], [112, 0], 0.0, true], ["scale_r", [3, -12, -4], [2, 4, 6], [0, 0], 0.0],
		["nostril_r", [3, -3, -22], [2, 2, 4], [112, 0], 0.0]]])
	parts.append(["jaw", [0, 4, -8], [-6, 0, -16], [12, 4, 16], [176, 65], 0])
	parts.append(["left_wing", [12, -11, 2], [0, -4, -4], [56, 8, 8], [112, 88], 0, 0, 0, 0.0, [["skin", [0, 0, 2], [56, 0, 56], [-56, 88], 0.0, true]], true])
	parts.append(["left_wing_tip", [56, 0, 0], [0, -2, -2], [56, 4, 4], [112, 136], 0, 0, 0, 0.0, [["skin", [0, 0, 2], [56, 0, 56], [-56, 144], 0.0, true]], true])
	parts.append(["right_wing", [-12, -11, 2], [-56, -4, -4], [56, 8, 8], [112, 88], 0, 0, 0, 0.0, [["skin", [-56, 0, 2], [56, 0, 56], [-56, 88], 0.0]]])
	parts.append(["right_wing_tip", [-56, 0, 0], [-56, -2, -2], [56, 4, 4], [112, 136], 0, 0, 0, 0.0, [["skin", [-56, 0, 2], [56, 0, 56], [-56, 144], 0.0]]])
	for sd in [["left", 1], ["right", -1]]:
		var n: String = sd[0]
		var sx: int = sd[1]
		parts.append([n + "_front_leg", [12 * sx, 4, 2], [-4, -4, -4], [8, 24, 8], [112, 104], 0])
		parts.append([n + "_front_leg_tip", [0, 20, -1], [-3, -1, -3], [6, 24, 6], [226, 138], 0])
		parts.append([n + "_front_foot", [0, 23, 0], [-4, 0, -12], [8, 4, 16], [144, 104], 0])
		parts.append([n + "_hind_leg", [16 * sx, 0, 42], [-8, -4, -8], [16, 32, 16], [0, 0], 0])
		parts.append([n + "_hind_leg_tip", [0, 32, -4], [-6, -2, 0], [12, 32, 12], [196, 0], 0])
		parts.append([n + "_hind_foot", [0, 31, 4], [-9, 0, -20], [18, 6, 24], [112, 0], 0])
	return parts


## Java EndCrystalModel: base plate, outer glass, inner glass, cube (the parts are placed per frame by
## EntityManager._crystal_pose: the model is not flipped and is drawn at scale 2).
const CRYSTAL := [["base", [0, 0, 0], [-6, 0, -6], [12, 4, 12], [0, 16], 0], ["outer_glass", [0, 0, 0], [-4, -4, -4], [8, 8, 8], [0, 0], 0],
	["inner_glass", [0, 0, 0], [-4, -4, -4], [8, 8, 8], [0, 0], 0], ["crystal_cube", [0, 0, 0], [-4, -4, -4], [8, 8, 8], [32, 0], 0]]


## Texture coverage of a mob's rig (Java box UV): [percent of opaque texels no box uses, low-opacity boxes]. Used by the
## --rigcheck probe and the vanilla tests.
static func coverage(id: String) -> Array:
	var d := MobRegistry.get_def(id)
	if d.is_empty() or not d.has("parts"):
		return [100, ["no rig"]]
	var img: Image = Res.load_image(str(d.get("tex", "")))
	if img == null:
		return [100, ["no texture"]]
	if img.is_compressed():
		img.decompress()
	var ts: Array = d.get("tex_size", [64, 64])
	var tw := int(ts[0])
	var th := int(ts[1])
	var sx := float(img.get_width()) / float(tw)
	var sy := float(img.get_height()) / float(th)
	var used := PackedByteArray()
	used.resize(tw * th)
	var bad: Array = []
	var boxes: Array = []
	for p in d["parts"]:
		boxes.append([str(p[0]), p[3], p[4]])
		if p.size() > 9 and p[9] is Array:
			for ex in p[9]:
				boxes.append([str(ex[0]), ex[2], ex[3]])
	for bx in boxes:
		var s: Array = bx[1]
		var uv: Array = bx[2]
		var w := int(ceil(absf(float(s[0]))))
		var h := int(ceil(absf(float(s[1]))))
		var dd := int(ceil(absf(float(s[2]))))
		var u := int(uv[0])
		var v := int(uv[1])
		var rects := [Rect2i(u + dd, v, w, dd), Rect2i(u + dd + w, v, w, dd), Rect2i(u, v + dd, dd, h), Rect2i(u + dd, v + dd, w, h),
			Rect2i(u + dd + w, v + dd, dd, h), Rect2i(u + 2 * dd + w, v + dd, w, h)]
		var tot := 0
		var opq := 0
		var outside := 0
		for r in rects:
			for yy in range(r.position.y, r.end.y):
				for xx in range(r.position.x, r.end.x):
					tot += 1
					if xx < 0 or yy < 0 or xx >= tw or yy >= th:
						outside += 1
						continue
					used[yy * tw + xx] = 1
					if img.get_pixel(int(xx * sx), int(yy * sy)).a > 0.05:
						opq += 1
		if tot > 0 and (float(opq) / tot < 0.6 or outside > 0):
			bad.append("%s %d%%%s" % [bx[0], int(100.0 * opq / tot), " OUT" if outside > 0 else ""])
	var unused := 0
	var opaque := 0
	for yy in th:
		for xx in tw:
			if img.get_pixel(int(xx * sx), int(yy * sy)).a > 0.05:
				opaque += 1
				if used[yy * tw + xx] == 0:
					unused += 1
	return [int(100.0 * unused / maxi(1, opaque)), bad]