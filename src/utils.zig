const std = @import("std");
const pw = @import("pipewire.zig");
const c = pw.c;

pub fn generateEventsStruct(version: u32, comptime EventsCType: type, comptime EventsUnion: type) EventsCType {
    var c_events: EventsCType = undefined;
    struct_fields_loop: inline for (@typeInfo(EventsCType).Struct.fields) |struct_field| {
        if (comptime std.mem.eql(u8, struct_field.name, "version")) {
            c_events.version = version;
            continue;
        }
        inline for (@typeInfo(EventsUnion).Union.fields) |union_field| {
            if (comptime std.mem.eql(u8, struct_field.name, union_field.name)) {
                if (@typeInfo(union_field.type) == .Pointer) {
                    const fns = struct {
                        pub fn func(_data: ?*anyopaque, arg1: ?*anyopaque) callconv(.C) void {
                            const ev = @unionInit(
                                EventsUnion,
                                union_field.name,
                                @ptrCast(@alignCast(arg1)),
                            );
                            const D = struct { f: *const fn (data: *anyopaque, event: EventsUnion) void, d: *anyopaque };
                            const listener: *D = @ptrCast(@alignCast(_data));
                            listener.f(listener.d, ev);
                        }
                    };
                    @field(c_events, struct_field.name) = @ptrCast(&fns.func);
                    continue :struct_fields_loop;
                }
                if (@typeInfo(union_field.type) == .Struct) {
                    const fns = struct {
                        pub fn func(_data: ?*anyopaque, arg1: usize, arg2: usize, arg3: usize, arg4: usize, arg5: usize) callconv(.C) void {
                            const args = .{ arg1, arg2, arg3, arg4, arg5 };
                            const ev_data = blk: {
                                if (@hasDecl(union_field.type, "fromArgs")) {
                                    break :blk @field(union_field.type, "fromArgs")(args);
                                } else {
                                    var r: union_field.type = undefined;
                                    inline for (@typeInfo(union_field.type).Struct.fields, 0..) |f, i| {
                                        const arg = args[i];
                                        comptime var ti = @typeInfo(f.type);
                                        if (ti == .Optional) {
                                            ti = @typeInfo(ti.Optional.child);
                                        }
                                        if (@Type(ti) == ([:0]const u8)) {
                                            const ptr: [*:0]const u8 = @ptrFromInt(arg);
                                            if (@typeInfo(f.type) == .Optional and (arg == 0 or ptr[0] == 0)) {
                                                @field(r, f.name) = null;
                                            } else {
                                                @field(r, f.name) = std.mem.span(ptr);
                                            }
                                        } else if (ti == .Pointer) {
                                            @field(r, f.name) = @ptrFromInt(arg);
                                        } else if (ti == .Int) {
                                            @field(r, f.name) = @intCast(arg);
                                        } else {
                                            @compileLog(@Type(ti));
                                            unreachable;
                                        }
                                    }
                                    break :blk r;
                                }
                            };
                            const ev = @unionInit(
                                EventsUnion,
                                union_field.name,
                                ev_data,
                            );
                            const D = struct { f: *const fn (data: *anyopaque, event: EventsUnion) void, d: *anyopaque };
                            const listener: *D = @ptrCast(@alignCast(_data));
                            listener.f(listener.d, ev);
                        }
                    };
                    @field(c_events, struct_field.name) = @ptrCast(&fns.func);
                    continue :struct_fields_loop;
                }
                unreachable;
            }
        }
        @field(c_events, struct_field.name) = null;
    }
    return c_events;
}

pub const Listener = struct {
    const Self = @This();
    pub const D = struct { f: *const anyopaque, d: *anyopaque };
    allocator: std.mem.Allocator,
    spa_hook: c.struct_spa_hook,
    cb: D,
    pub fn init(
        allocator: std.mem.Allocator,
        listener: *const anyopaque,
        data: *anyopaque,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .spa_hook = std.mem.zeroes(c.struct_spa_hook),
            .cb = .{ .f = listener, .d = data },
        };
        return self;
    }
    pub fn deinit(self: *Self) void {
        c.spa_hook_remove(&self.spa_hook);
        self.allocator.destroy(self);
    }
};
