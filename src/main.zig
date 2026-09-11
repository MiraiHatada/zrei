const std = @import("std");

pub fn main(init: std.process.Init) u8 {
    std.Io.File.writeStreamingAll(.stdout(), init.io, "hi\n") catch {};
    return 0;
}
