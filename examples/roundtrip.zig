const std = @import("std");
const ArrayList = std.ArrayList;
const pw = @import("pipewire");
const pretty = @import("pretty");

const Global = struct {
    id: u32,
    permissions: u32,
    typ: pw.ObjType,
    listener: ?*pw.utils.Listener = null,
    proxy: *pw.Proxy,
    version: u32,
    props: std.StringArrayHashMap([]const u8),
    pub fn deinit(self: *Global) void {
        if (self.listener) |l| {
            l.deinit();
        }
        self.proxy.destroy();

        var it = self.props.iterator();
        while (it.next()) |prop| {
            self.props.allocator.free(prop.key_ptr.*);
            self.props.allocator.free(prop.value_ptr.*);
        }
        self.props.deinit();
    }
};

const RemoteData = struct {
    allocator: std.mem.Allocator,
    registry: *pw.Registry,
    core: *pw.Core,
    loop: *pw.MainLoop,
    globals: std.AutoHashMap(u32, Global),
    default_sink_id: ?u32 = null,
    pub fn deinit(self: *RemoteData) void {
        var it = self.globals.valueIterator();
        while (it.next()) |g| {
            g.deinit();
        }
        self.globals.deinit();
    }
};

pub fn coreListener(data: *RemoteData, event: pw.Core.Event) void {
    _ = data;
    _ = event;
    std.debug.print("DONE\n", .{});
}
pub fn deviceListener(data: *RemoteData, event: pw.Device.Event) void {
    switch (event) {
        .info => |e| {
            var g = data.globals.getPtr(e.id).?;
            std.debug.assert(g.typ == .Device);

            std.debug.print("DEVICE INFO {} - {?s} - {} props - {} params\n", .{
                e.id,
                g.props.get("device.name"),
                e.props.asSlice().len,
                e.n_params,
            });

            if (e.props.n_items > 0) {
                g.props = blk: {
                    var it = g.props.iterator();
                    while (it.next()) |prop| {
                        g.props.allocator.free(prop.key_ptr.*);
                        g.props.allocator.free(prop.value_ptr.*);
                    }
                    g.props.deinit();
                    break :blk e.props.toArrayHashMap(data.allocator);
                };
            }
            for (e.getParamInfos()) |pi| {
                var node = g.proxy.downcast(pw.Device);
                // if (pi.id == .Props and e.id == data.default_sink_id.?) {
                _ = node.enumParams(0, pi.id, 0, 0, null);
                std.debug.print("{}\n", .{pi});
                // }
            }
        },
        .param => |param| {
            // std.debug.print("\nPARAM:\n", .{});
            var copy = param.spa_pod.copy(data.allocator) catch unreachable;
            copy.deinit(data.allocator);
            // var tree = param.spa_pod.toJsonTree(data.allocator) catch unreachable;
            // tree.root.dump();
            // tree.deinit();
            // std.debug.print("\n", .{});
        },
    }
}
pub fn nodeListener(data: *RemoteData, event: pw.Node.Event) void {
    switch (event) {
        .info => |e| {
            var g = data.globals.getPtr(e.id).?;
            std.debug.assert(g.typ == .Node);

            std.debug.print("INFO {} - {?s} - {} props - {} params\n", .{
                e.id,
                g.props.get("node.name"),
                e.props.asSlice().len,
                e.n_params,
            });

            if (e.props.n_items > 0) {
                g.props = blk: {
                    var it = g.props.iterator();
                    while (it.next()) |prop| {
                        g.props.allocator.free(prop.key_ptr.*);
                        g.props.allocator.free(prop.value_ptr.*);
                    }
                    g.props.deinit();
                    break :blk e.props.toArrayHashMap(data.allocator);
                };
            }
            // for (e.getParamInfos()) |pi| {
            //     var node = g.proxy.downcast(pw.Node);
            //     if (pi.id == .Props and e.id == data.default_sink_id.?) {
            //         _ = node.enumParams(0, pi.id, 0, 0, null);
            //         std.debug.print("{}\n", .{pi});
            //     }
            // }
        },
        .param => |_| {
            // std.debug.print("\nPARAM:\n", .{});
            // var copy = param.spa_pod.copy(data.allocator) catch unreachable;
            // copy.deinit(data.allocator);
            // var tree = param.spa_pod.toJsonTree(data.allocator) catch unreachable;
            // tree.root.dump();
            // tree.deinit();
            // std.debug.print("\n", .{});
        },
    }
}
pub fn metadataListener(data: *RemoteData, event: pw.Metadata.Event) void {
    const prop = event.property;
    if (prop.type != null and std.mem.eql(u8, prop.type.?, "Spa:String:JSON")) {
        var tree = std.json.parseFromSlice(std.json.Value, data.allocator, prop.value, .{}) catch {
            // std.debug.print("cannot parse json property {any} {s}\n", .{ event, prop.value });
            return;
        };
        defer tree.deinit();

        std.debug.print("\n metadata: \n{s}\n---\n", .{prop.value});

        if (std.mem.eql(u8, prop.key, "default.audio.sink")) {
            const default_sink = tree.value.object.get("name").?.string;

            var it = data.globals.valueIterator();
            while (it.next()) |g| {
                if (g.typ == .Node) {
                    if (g.props.get("node.name")) |name| {
                        if (std.mem.eql(u8, name, default_sink)) {
                            data.default_sink_id = g.id;
                            break;
                        }
                    }
                }
            } else {
                unreachable;
            }
        }
    }
}

pub fn registryListener(data: *RemoteData, event: pw.Registry.Event) void {
    std.debug.print("\n----\nListener got event: \n------\n, {any}", .{event});

    pretty.print(data.allocator, event.global.props.asSlice(), .{}) catch return;
    switch (event) {
        .global => |e| {
            if (e.typ == .Profiler) return;

            data.globals.putNoClobber(e.id, .{
                .id = e.id,
                .typ = e.typ,
                .permissions = e.permissions,
                .proxy = data.registry.bind(e) catch unreachable,
                .version = e.version,
                .props = e.props.toArrayHashMap(data.allocator),
            }) catch unreachable;

            var g = data.globals.getPtr(e.id) orelse unreachable;

            // std.debug.print("GLOBAL added : id:{} type:{} v:{}\n", .{ e.id, e.typ, e.version });
            switch (e.typ) {
                .Node => {
                    std.debug.print("Node {} props: {}\n\n", .{ e.id, e.props });
                    var node = g.proxy.downcast(pw.Node);
                    const listener = node.addListener(data.allocator, RemoteData, data, nodeListener);
                    g.listener = listener;
                },
                .Device => {
                    std.debug.print("device: {}\n\n", .{e.props});
                    var device = g.proxy.downcast(pw.Device);
                    const listener = device.addListener(data.allocator, RemoteData, data, deviceListener);
                    g.listener = listener;
                },
                .Metadata => {
                    // std.debug.print("METADATA: \n", .{});
                    var metadata = g.proxy.downcast(pw.Metadata);
                    const listener = metadata.addListener(data.allocator, RemoteData, data, metadataListener);
                    g.listener = listener;
                },
                else => {},
            }
        },
        .global_remove => |e| {
            const kv = data.globals.fetchRemove(e.id).?;
            var g = kv.value;
            std.debug.print("GLOBAL REMOVED  {} {} {?s}!!!!!!!\n", .{ e.id, g.typ, g.props.get("node.name") });
            g.deinit();
        },
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    pw.c.pw_init(null, null);
    defer pw.c.pw_deinit();

    std.debug.print("{s}\n{s}\n", .{
        pw.c.pw_get_headers_version(),
        pw.c.pw_get_library_version(),
    });

    var loop = try pw.MainLoop.new();
    defer loop.destroy();

    var context = try pw.Context.new(loop.getLoop());
    defer context.destroy();

    var core = try context.connect(@sizeOf(RemoteData));
    defer core.disconnect();

    var registry = try core.getRegistry();
    defer registry.destroy();

    const rd = core.asProxy().getUserData(RemoteData);
    defer rd.deinit();
    rd.* = .{
        .globals = @TypeOf(rd.globals).init(allocator),
        .allocator = allocator,
        .registry = registry,
        .core = core,
        .loop = loop,
    };

    // TODO: Do not assume passed type is a pointer
    var regitry_hook = registry.addListener(allocator, RemoteData, rd, registryListener);
    defer regitry_hook.deinit();

    try roundtrip(loop, core, allocator);
    try roundtrip(loop, core, allocator);
    try roundtrip(loop, core, allocator);

    var default_sink = rd.globals.get(rd.default_sink_id.?).?;
    // var node = default_sink.proxy.downcast(pw.Node);

    // var b = pw.spa.pod.Builder.init(rd.allocator);
    // defer b.deinit();

    // try b.add(.Object, .{
    //     .{ .mute, .{ .Bool, .{@as(u32, 1)} } },
    // });

    // const res = node.setParam(pw.c.SPA_PARAM_Props, 0, b.deref());
    // std.debug.print("res {}\n", .{res});

    // try roundtrip(loop, core, allocator);
    // try roundtrip(loop, core, allocator);
    // try roundtrip(loop, core, allocator);

    std.debug.print("default sink: {} {?s} {?s}\n", .{
        rd.default_sink_id.?,
        default_sink.props.get("node.name"),
        default_sink.props.get("device.id"),
    });
}

pub fn roundtrip(loop: *pw.MainLoop, core: *pw.Core, allocator: std.mem.Allocator) !void {
    _ = core.sync(pw.c.PW_ID_CORE, 0);
    const l = struct {
        pub fn coreListener(_loop: *pw.MainLoop, event: pw.Core.Event) void {
            _ = event;
            _loop.quit();
            std.debug.print("DONE\n", .{});
        }
    }.coreListener;

    var core_hook = core.addListener(allocator, pw.MainLoop, loop, &l);
    defer core_hook.deinit();

    loop.run();
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
