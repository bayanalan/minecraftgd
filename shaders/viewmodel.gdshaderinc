// First-person hand / held item drawn in the main view (ViewModel): with VIEWMODEL defined (variant shaders built by
// ViewModel), VM_POSITION in vertex() re-projects the camera-relative geometry with Java's fixed 70 degree hand FOV
// (vm_fov_scale = tan(camera fov / 2) / tan(35 deg)) and packs its depth into the nearest 2% of the reverse-Z range,
// so the hand never clips into terrain and always draws over the world (Java clears depth before the hand pass).
// Without VIEWMODEL the hook expands to nothing.
#ifdef VIEWMODEL
global uniform float vm_fov_scale;

vec4 vm_clip(mat4 proj, vec4 view) {
	vec4 c = proj * view;
	c.xy *= vm_fov_scale;
	float d = max(-view.z, 0.001);
	c.z = c.w * (0.98 + 0.02 * clamp(0.01 / d, 0.0, 1.0));
	return c;
}
#define VM_POSITION POSITION = vm_clip(PROJECTION_MATRIX, MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
#else
#define VM_POSITION
#endif
