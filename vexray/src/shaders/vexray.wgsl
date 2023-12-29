// CONSTANTS_START
const INF_F32 = 0x1p+127f;
// CONSTANTS_END

// IMAGE_START
struct Image {
    width: u32,
    height: u32,
}
// IMAGE_END

// CAMERA_START
struct Camera {
    center: vec3f,
    focal_length: f32
}
// CAMERA_END

// VIEWPORT_START
struct Viewport {
    width: f32,
    height: f32,
    u: vec3f,
    v: vec3f,
    delta_u: vec3f,
    delta_v: vec3f,
    upper_left: vec3f,
}
// VIEWPORT_END

// CONFIG_START
struct Config {
    image: Image,
    camera: Camera,
    viewport: Viewport,
    pixel_zero_loc: vec3f
}
// CONFIG_END

// UTILS_START
fn vec3f_len_squared(v: vec3f) -> f32 {
    return v.x * v.x + v.y * v.y + v.z * v.z;
}
// UTILS_END

// RAY_START
struct HitRecord {
    point: vec3f,
    normal: vec3f,
    t: f32,
    front_face: bool
}

struct Ray {
    origin: vec3f,
    direction: vec3f
}

fn ray_at(ray: Ray, t: f32) -> vec3f {
    return ray.origin + t * ray.direction;
}

fn ray_color(ray: Ray) -> vec3f {
    var hit = HitRecord();

    if hit_world(ray, 0.0, INF_F32, &hit) {
        return 0.5 * (hit.normal + vec3f(1.0));
    }

    let unit_dir = normalize(ray.direction);
    let alpha = 0.5 * (unit_dir.y + 1.0);
    return (1.0 - alpha) * vec3f(1.0, 1.0, 1.0) + alpha * vec3f(0.3, 0.6, 1.0); // lerp
}

/// Uses dot product to figure out which side the ray is
/// out_normal needs to be a unit vector
fn hit_set_face_normal(hit: ptr<function, HitRecord>, ray: Ray, out_normal: vec3f) {
    let front_face = dot(ray.direction, out_normal) < 0.0;
    let normal = select(-out_normal, out_normal, front_face);

    (*hit).front_face = front_face;
    (*hit).normal = normal;
}
// RAY_END

// hit interface
// fn hit(shape: Shape, ray: Ray, rmin: f32, rmax: f32, hit: ptr<function, HitRecord>) -> bool {}

// SPHERE_START
struct Sphere {
    center: vec3f,
    radius: f32
}

/// solves the sphere ray intersection equation, which is a quadratic equation
fn hit_sphere(sphere: Sphere, ray: Ray, rmin: f32, rmax: f32, hit: ptr<function, HitRecord>) -> bool {
    let origin_to_center = ray.origin - sphere.center; // A - C

    let a = vec3f_len_squared(ray.direction);
    let half_b = dot(origin_to_center, ray.direction);
    let c = vec3f_len_squared(origin_to_center) - sphere.radius * sphere.radius;

    let discriminant = half_b * half_b - a * c;

    if discriminant < 0.0 {
        return false;
    }

    let sqrtd = sqrt(discriminant);

    var root = (-half_b - sqrtd) / a;
    if root <= rmin || root >= rmax {
        root = (-half_b + sqrtd) / a;
        if root <= rmin || root >= rmax {
            return false;
        }
    }

    let point = ray_at(ray, root);
    let out_normal = (point - sphere.center) / sphere.radius; // this will be unit length

    (*hit).t = root;
    (*hit).point = point;
    hit_set_face_normal(hit, ray, out_normal);

    return true;
}
// SPHERE_END

// WORLD_START
fn hit_world(ray: Ray, rmin: f32, rmax: f32, hit: ptr<function, HitRecord>) -> bool {
    var temp_hit = HitRecord();
    var hit_anything = false;
    var closest_so_far = rmax;

    // arrayLength returns a u32, so we make i also u32 to make logical operation happy
    for (var i = 0u; i < arrayLength(&world); i++) {
        let sphere = world[i];

        if hit_sphere(sphere, ray, rmin, closest_so_far, &temp_hit) {
            hit_anything = true;
            closest_so_far = temp_hit.t;
            *hit = temp_hit;
        }
    }

    return hit_anything;
}
// WORLD_END

// BINDINGS_START
@group(0) @binding(0) var result: texture_storage_2d<rgba8unorm, write>; // output image
@group(0) @binding(1) var<uniform> config: Config; // render config
@group(0) @binding(2) var<storage, read> world: array<Sphere>;
// BINDINGS_END

@compute @workgroup_size(1, 1, 1)
fn main(@builtin(global_invocation_id) id: vec3u) {
    let pixel_position = vec2i(i32(id.x), i32(id.y));

    let pixel_center = config.pixel_zero_loc 
        + (f32(pixel_position.x) * config.viewport.delta_u) 
        + (f32(pixel_position.y) * config.viewport.delta_v);
    
    let ray_direction = pixel_center - config.camera.center;

    let ray = Ray(config.camera.center, ray_direction);

    var pixel_color = ray_color(ray);

    textureStore(result, pixel_position, vec4f(pixel_color, 1.0)); // final output
}