#include "common.glsl"

// Position the origin to the upper left
layout(origin_upper_left) in vec4 gl_FragCoord;

// Must declare this output for some versions of OpenGL.
layout(location = 0) out vec4 out_FragColor;

layout(binding = 1, std430) readonly buffer bg_cells {
    uint cells[];
};

bool same(ivec2 grid_pos, ivec2 offset, ivec2 grid_size, uint packed_color) {
    ivec2 neighbor = grid_pos + offset;
    if (neighbor.x < 0) return (padding_extend & EXTEND_LEFT) != 0;
    if (neighbor.x >= grid_size.x) return (padding_extend & EXTEND_RIGHT) != 0;
    if (neighbor.y < 0) return (padding_extend & EXTEND_UP) != 0;
    if (neighbor.y >= grid_size.y) return (padding_extend & EXTEND_DOWN) != 0;
    return cells[neighbor.y * grid_size.x + neighbor.x] == packed_color;
}

vec4 cell_bg() {
    uvec2 grid_size = unpack2u16(grid_size_packed_2u16);
    ivec2 grid_pos = ivec2(floor((gl_FragCoord.xy - grid_padding.wx) / cell_size));
    bool inside_grid = all(greaterThanEqual(grid_pos, ivec2(0))) &&
        all(lessThan(grid_pos, ivec2(grid_size)));
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0;

    vec4 bg = vec4(0.0);

    // Clamp x position, extends edge bg colors in to padding on sides.
    if (grid_pos.x < 0) {
        if ((padding_extend & EXTEND_LEFT) != 0) {
            grid_pos.x = 0;
        } else {
            return bg;
        }
    } else if (grid_pos.x > grid_size.x - 1) {
        if ((padding_extend & EXTEND_RIGHT) != 0) {
            grid_pos.x = int(grid_size.x) - 1;
        } else {
            return bg;
        }
    }

    // Clamp y position if we should extend, otherwise discard if out of bounds.
    if (grid_pos.y < 0) {
        if ((padding_extend & EXTEND_UP) != 0) {
            grid_pos.y = 0;
        } else {
            return bg;
        }
    } else if (grid_pos.y > grid_size.y - 1) {
        if ((padding_extend & EXTEND_DOWN) != 0) {
            grid_pos.y = int(grid_size.y) - 1;
        } else {
            return bg;
        }
    }

    // Load the color for the cell.
    uint packed_color = cells[grid_pos.y * int(grid_size.x) + grid_pos.x];
    vec4 cell_color = load_color(
            unpack4u8(packed_color),
            use_linear_blending
        );

    if ((bools & BOX_ROUND) == 0 || cell_color.a <= 0.0 || !inside_grid) {
        return cell_color;
    }

    ivec2 grid_size_i = ivec2(grid_size);
    bool left = !same(grid_pos, ivec2(-1, 0), grid_size_i, packed_color);
    bool right = !same(grid_pos, ivec2(1, 0), grid_size_i, packed_color);
    bool top = !same(grid_pos, ivec2(0, -1), grid_size_i, packed_color);
    bool bottom = !same(grid_pos, ivec2(0, 1), grid_size_i, packed_color);

    vec2 p = mod(gl_FragCoord.xy - grid_padding.wx, cell_size);
    float radius = min(cell_size.x, cell_size.y) * 0.8;
    float outline_width = max(1.0, floor(min(cell_size.x, cell_size.y) / 14.0));
    float corner_coverage = 1.0;
    bool in_corner = false;
    bool corner_outline = false;

    if (left && top && p.x < radius && p.y < radius) {
        float d = distance(p, vec2(radius, radius));
        corner_coverage = clamp(radius - d + 0.5, 0.0, 1.0);
        corner_outline = d > radius - outline_width;
        in_corner = true;
    } else if (right && top && p.x >= cell_size.x - radius && p.y < radius) {
        float d = distance(p, vec2(cell_size.x - radius, radius));
        corner_coverage = clamp(radius - d + 0.5, 0.0, 1.0);
        corner_outline = d > radius - outline_width;
        in_corner = true;
    } else if (left && bottom && p.x < radius && p.y >= cell_size.y - radius) {
        float d = distance(p, vec2(radius, cell_size.y - radius));
        corner_coverage = clamp(radius - d + 0.5, 0.0, 1.0);
        corner_outline = d > radius - outline_width;
        in_corner = true;
    } else if (right && bottom && p.x >= cell_size.x - radius && p.y >= cell_size.y - radius) {
        float d = distance(p, vec2(cell_size.x - radius, cell_size.y - radius));
        corner_coverage = clamp(radius - d + 0.5, 0.0, 1.0);
        corner_outline = d > radius - outline_width;
        in_corner = true;
    }

    vec3 rgb = cell_color.rgb / cell_color.a;
    vec4 outline_color = vec4(mix(rgb, vec3(1.0), 0.3), max(cell_color.a, 0.65));
    outline_color.rgb *= outline_color.a;

    if (in_corner) {
        if (corner_coverage <= 0.0) return vec4(0.0);
        vec4 color = corner_outline ? outline_color : cell_color;
        return color * corner_coverage;
    }

    if ((left && p.x < outline_width) ||
        (right && p.x >= cell_size.x - outline_width) ||
        (top && p.y < outline_width) ||
        (bottom && p.y >= cell_size.y - outline_width)) {
        return outline_color;
    }

    return cell_color;
}

void main() {
    out_FragColor = cell_bg();
}
