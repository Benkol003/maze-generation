const std = @import("std");
const rl = @import("raylib");
//const stack = @import("stack.zig");

const Allocator = std.mem.Allocator;

//number of tiles
const MapHeight = 100;
const MapWidth = 100;

const WindowHeight = 1000;
const WindowWidth = 1000;
const TileWidth = WindowWidth / MapWidth;
const TileHeight = WindowHeight / MapHeight;

const TileMasks = struct {
    const BorderTop: u8 = 0b1;
    const BorderRight: u8 = 0b10;
    const BorderBottom: u8 = 0b100;
    const BorderLeft: u8 = 0b1000;
    const Visited: u8 = 0b10000;
    const StartTile: u8 = 0b100000;
    const EndTile: u8 = 0b1000000;
};

//[x][y] access
var tiles: [MapWidth][MapHeight]u8 = [_][MapHeight]u8{[_]u8{0b1111} ** MapHeight} ** MapWidth;

//todo doesnt draw left border edges at x=0
fn drawPass(dfs_args: DfsArgs) void {
    rl.beginDrawing();
    rl.clearBackground(rl.Color.black);

    for (dfs_args.path.items) |i| {
        rl.drawRectangle(@intCast(i.x * TileWidth + 1), @intCast(i.y * TileHeight), TileWidth, TileHeight, rl.Color.dark_green);
    }

    rl.drawRectangle(@intCast(dfs_args.finish.x * TileWidth + 1), @intCast(dfs_args.finish.y * TileHeight), TileWidth, TileHeight, rl.Color.green);

    for (0..MapWidth) |x| {
        for (0..MapHeight) |y| {
            const wx: i32 = @intCast(x * TileWidth + 1); //TODO RM +1 hack to display left border
            const wy: i32 = @intCast(y * TileHeight);
            const tile = tiles[x][y];
            if (tile & TileMasks.Visited == 0) {
                rl.drawRectangle(wx, wy, TileWidth, TileHeight, rl.Color.black);
            } else {
                if (tile & TileMasks.StartTile != 0) {
                    rl.drawRectangle(wx, wy, TileWidth, TileHeight, rl.Color.red);
                }
                if ((tile & TileMasks.BorderTop) != 0) {
                    rl.drawLine(wx, wy, wx + TileWidth - 1, wy, rl.Color.white);
                }
                if (tile & TileMasks.BorderRight != 0) {
                    rl.drawLine(wx + TileWidth - 1, wy, wx + TileWidth - 1, wy + TileHeight - 1, rl.Color.white);
                }
                if ((tile & TileMasks.BorderBottom) != 0) {
                    rl.drawLine(wx, wy + TileHeight - 1, wx + TileWidth - 1, wy + TileHeight - 1, rl.Color.white);
                }
                if ((tile & TileMasks.BorderLeft) != 0) {
                    rl.drawLine(wx, wy, wx, wy + TileHeight - 1, rl.Color.white);
                }
            }
        }
    }
    rl.endDrawing();
}

//center of maze can be deepest tile reached by DFS
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const Idx = struct { x: usize, y: usize };

const DfsArgs = struct { stack: *std.ArrayList(Idx), map: *[MapWidth][MapHeight]u8, allocator: Allocator, finish: Idx, finish_depth: usize, path: std.ArrayList(Idx) };

fn dfs_iter(dfs_args: *DfsArgs) !bool { //returns true when finished.
    const current = dfs_args.stack.getLast();
    if (dfs_args.stack.items.len == 1 and (dfs_args.map[current.x][current.y] & TileMasks.Visited != 0)) return true;

    //visit here so can check end condition - if at start tile and is visited i.e. reached by backtracking and not start of DFS
    dfs_args.map[current.x][current.y] |= TileMasks.Visited;

    var unvisited = try std.ArrayList(Idx).initCapacity(dfs_args.allocator, 4);

    if (dfs_args.stack.items.len > dfs_args.finish_depth) {
        dfs_args.finish_depth = dfs_args.stack.items.len;
        dfs_args.finish = current;
        dfs_args.path = try dfs_args.stack.clone();
    }

    //check for unvisited neighbours
    if (current.x != 0) {
        if (dfs_args.map[current.x - 1][current.y] & TileMasks.Visited == 0)
            try unvisited.append(Idx{ .x = current.x - 1, .y = current.y });
    }
    if (current.y != 0) {
        if (dfs_args.map[current.x][current.y - 1] & TileMasks.Visited == 0)
            try unvisited.append(Idx{ .x = current.x, .y = current.y - 1 });
    }
    if (current.x != MapWidth - 1) {
        if (dfs_args.map[current.x + 1][current.y] & TileMasks.Visited == 0)
            try unvisited.append(Idx{ .x = current.x + 1, .y = current.y });
    }
    if (current.y != MapHeight - 1) {
        if (dfs_args.map[current.x][current.y + 1] & TileMasks.Visited == 0)
            try unvisited.append(Idx{ .x = current.x, .y = current.y + 1 });
    }
    if (unvisited.items.len == 0) { //backtrack
        _ = dfs_args.stack.pop();
    } else {
        var prng = std.rand.DefaultPrng.init(@intCast(std.time.nanoTimestamp())); //TODO use next() instead of nano timestamp
        const rndn = @mod(prng.random().int(usize), unvisited.items.len);

        const chosen = unvisited.items[rndn];

        //remove walls
        if (current.x != 0 and chosen.x == current.x - 1) {
            dfs_args.map[current.x][current.y] &= ~TileMasks.BorderLeft;
            dfs_args.map[chosen.x][chosen.y] &= ~TileMasks.BorderRight;
        } else if (current.x != MapWidth - 1 and chosen.x == current.x + 1) {
            dfs_args.map[current.x][current.y] &= ~TileMasks.BorderRight;
            dfs_args.map[chosen.x][chosen.y] &= ~TileMasks.BorderLeft;
        } else if (current.y != 0 and chosen.y == current.y - 1) {
            dfs_args.map[current.x][current.y] &= ~TileMasks.BorderTop;
            dfs_args.map[chosen.x][chosen.y] &= ~TileMasks.BorderBottom;
        } else if (current.y != MapHeight and chosen.y == current.y + 1) {
            dfs_args.map[current.x][current.y] &= ~TileMasks.BorderBottom;
            dfs_args.map[chosen.x][chosen.y] &= ~TileMasks.BorderTop;
        } else {
            unreachable;
        }

        try dfs_args.stack.append(chosen);
    }
    return false;
}

pub fn main() !void {
    var stack = try std.ArrayList(Idx).initCapacity(gpa.allocator(), TileHeight * TileWidth);
    defer stack.deinit();

    rl.initWindow(WindowWidth, WindowHeight, "zig raylib window");

    //start tile
    tiles[5][0] = tiles[5][0] | TileMasks.StartTile;
    try stack.append(Idx{ .x = 5, .y = 0 });

    var exit = false;
    var dfs_complete = false;
    var iteration: u32 = 0;

    var dfs_args = DfsArgs{
        .allocator = gpa.allocator(),
        .finish = Idx{ .x = 5, .y = 0 },
        .finish_depth = 0,
        .map = &tiles,
        .stack = &stack,
        .path = try stack.clone(),
    };

    while (!exit) {
        if (rl.isKeyPressed(rl.KeyboardKey.escape) or rl.windowShouldClose()) exit = true;
        for (0..1) |_| {
            if (!dfs_complete) {
                iteration += 1;
                //std.debug.print("iteration: {d}\n", .{iteration});
                dfs_complete = try dfs_iter(&dfs_args);
                if (dfs_complete) std.debug.print("finished DFS after {d} iterations.\n", .{iteration});
            }
        }
        drawPass(dfs_args);
    }
}
