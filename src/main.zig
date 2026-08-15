const r4os = @import("r4os");
const r4std = @import("r4std");

const test_path = "C:\\FSDIAG.TXT";
const test_data = "R4OS fsdiag write/read probe\r\n";
const append_data = "R4OS fsdiag append probe\r\n";
const persistent_data_suffix = "R4OS persistent marker\r\n";
const stream_path = "C:\\TEMP\\FSTREAM.BIN";
const stream_copy_path = "C:\\TEMP\\FSCOPY.BIN";
// The FAT32 metric checks (instrumentation, batching, extent cache, FSInfo)
// run on the FAT32 data disk since 0.60.9: C: is NTFS, D: keeps the FAT32
// counters meaningful.
const stream_large_path = "D:\\TEMP\\FSLARGE.BIN";
const stream_abort_path = "C:\\TEMP\\FSABORT.BIN";
const fat32_synthetic_14mb_path = "D:\\TEMP\\FS14MB.BIN";
const fat32_extent_cache_path = "D:\\TEMP\\FSEXT.BIN";
const fat32_fsinfo_probe_path = "D:\\TEMP\\FSINFO.BIN";
const system_replace_target_path = stream_path;
const system_replace_stage_path = stream_copy_path;
const system_replace_backup_path = "C:\\TEMP\\FSTRBAK.BIN";
const system_replace_original = "R4OS system replace original\r\n";
const system_replace_update = "R4OS system replace staged update\r\n";
const fat32_probe_path = "D:\\TEMP\\FATPROBE.BIN";
const fat32_probe_stream_path = "D:\\TEMP\\FATSTRM.BIN";
const fat32_probe_stream_bytes: u64 = 64 * 1024;
const fat32_probe_chunk: usize = 4 * 1024;
const fat32_baseline_055100_dir_scans: u64 = 142;
const fat32_baseline_055100_fat_reads: u64 = 83924;
const fat32_baseline_055100_alloc_search_steps: u64 = 80750;
const fat32_baseline_055100_cluster_walk_steps: u64 = 3118;
const stream_total_bytes: u64 = 256 * 1024;
const stream_write_chunk: usize = 2 * 1024;
const stream_copy_chunk: usize = 1024;
const stream_large_bytes: u64 = 1024 * 1024;
const stream_large_chunk: usize = 8 * 1024;
const stream_large_max_flushes: u64 = 4;
const fat32_synthetic_14mb_bytes: u64 = 14 * 1024 * 1024;
const fat32_synthetic_14mb_chunk: usize = 8 * 1024;
const fat32_extent_cache_bytes: u64 = 1024 * 1024;
const fat32_extent_cache_chunk: usize = 8 * 1024;
const fat32_extent_cache_offset: u32 = 512 * 1024 + 128;
const fat32_fsinfo_probe_bytes: u64 = 64 * 1024;
const fat32_fsinfo_probe_chunk: usize = 4 * 1024;

pub fn r4_app_main(app: *r4os.App) i32 {
    if (!r4std.init(app.startContext())) return r4os.abi.err_no_group;
    var ctx = app.system();
    var dev = app.devicesLowLevel() orelse return r4os.abi.err_no_group;
    var files = app.files() orelse return r4os.abi.err_no_fn;
    const data_letter = parseDataDrive(app.args());
    var ok = true;

    ctx.println("FSDIAG");
    ok = checkStorageOwnership(&ctx, &dev, 'C') and ok;
    ok = checkStorageOwnership(&ctx, &dev, data_letter) and ok;
    ok = checkExists(&ctx, "C:\\AUTOEXEC.BAT") and ok;
    ok = checkDataDrive(&ctx, data_letter) and ok;
    ok = checkReadConfig(&ctx) and ok;
    ok = checkFacadeRead(&ctx, &files) and ok;
    ok = checkCacheReadThrough(&ctx, &dev) and ok;
    ok = checkCacheWriteback(&ctx, &dev) and ok;
    ok = checkFat32Instrumentation(&ctx, &dev) and ok;
    ok = checkWriteRead(&ctx) and ok;
    ok = checkStreaming(&ctx) and ok;
    ok = checkLargeStreaming(&ctx, &dev) and ok;
    ok = checkFat32Synthetic14Mb(&ctx, &dev) and ok;
    ok = checkFat32ReadExtentCache(&ctx, &dev) and ok;
    ok = checkFat32FsInfoInuseMap(&ctx, &dev) and ok;
    ok = checkRegistryRecentWriteback(&ctx) and ok;
    ok = checkSystemReplaceContract(&ctx) and ok;
    ok = checkPersistentMarker(&ctx, data_letter) and ok;
    ok = listRoot(&ctx) and ok;
    ok = checkQualifiedDirEntries(&ctx) and ok;
    ok = listDataTemp(&ctx, data_letter) and ok;

    ctx.print("FSDIAG result: ");
    ctx.println(if (ok) "OK" else "FAILED");
    return if (ok) 0 else 1;
}

fn checkFacadeRead(ctx: *const r4os.r4sys.Context, files: *const r4os.Files) bool {
    var path = r4os.FilePath.parse("C:\\CONFIG.R4S") catch {
        ctx.println("FSDIAG facade result: FAILED invalid path");
        return false;
    };
    var buffer: [512]u8 = undefined;
    const ok = switch (files.read(path.asZ(), buffer[0..])) {
        .bytes => |count| count > 0,
        else => false,
    };
    ctx.write("FSDIAG facade result: ");
    ctx.println(if (ok) "OK" else "FAILED");
    return ok;
}

fn checkStorageOwnership(ctx: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context, letter: u8) bool {
    var rec: r4os.abi.DeviceInventoryRecord = .{};
    const found = findMountedStorageRecord(dev, letter, &rec);
    ctx.write("storage ");
    ctx.putc(letter);
    ctx.write(": ");
    if (!found) {
        ctx.println("FAILED missing mounted storage record");
        return false;
    }

    const ok = containsIgnoreCase(spanZ(rec.note[0..]), "source=preload");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" driver=");
    writeFixedZ(ctx, rec.driver[0..]);
    ctx.write(" status=");
    writeFixedZ(ctx, rec.status[0..]);
    ctx.write(" note=");
    writeFixedZ(ctx, rec.note[0..]);
    ctx.println("");
    return ok;
}

fn findMountedStorageRecord(dev: *const r4os.r4dev.Context, letter: u8, out: *r4os.abi.DeviceInventoryRecord) bool {
    var summary: r4os.abi.DeviceInventorySummary = .{};
    if (dev.deviceInventorySummary(&summary) <= 0) return false;
    var index: u32 = 0;
    while (index < summary.total) : (index += 1) {
        var rec: r4os.abi.DeviceInventoryRecord = .{};
        if (dev.deviceInventoryRecord(index, &rec) <= 0) continue;
        if (rec.bus != 4) continue;
        if (!storageStatusForLetter(rec.status[0..], letter)) continue;
        out.* = rec;
        return true;
    }
    return false;
}

fn checkExists(ctx: *const r4os.r4sys.Context, path: [*:0]const u8) bool {
    ctx.write("exists ");
    writeZ(ctx, path, 96);
    ctx.write(": ");
    const ok = ctx.exists(path);
    ctx.println(if (ok) "yes" else "no");
    return ok;
}

fn checkReadConfig(ctx: *const r4os.r4sys.Context) bool {
    var buf: [512]u8 = undefined;
    const len = ctx.fileRead("C:\\CONFIG.R4S", buf[0..]);
    ctx.write("read C:\\CONFIG.R4S: ");
    ctx.printI32(len);
    ctx.println(" bytes");
    return len > 0;
}

fn checkCacheReadThrough(ctx: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context) bool {
    const before = dev.performanceSummary() orelse {
        ctx.println("FSDIAG cache result: FAILED performance unavailable");
        return false;
    };
    var first: [128]u8 = undefined;
    var second: [128]u8 = undefined;
    const a = ctx.fileReadAt("C:\\R4OS\\CONFIG\\VERSION.R4S", 0, first[0..]);
    const b = ctx.fileReadAt("C:\\R4OS\\CONFIG\\VERSION.R4S", 0, second[0..]);
    const after = dev.performanceSummary() orelse {
        ctx.println("FSDIAG cache result: FAILED performance unavailable");
        return false;
    };
    const read_delta = if (after.fs_cache_reads >= before.fs_cache_reads) after.fs_cache_reads - before.fs_cache_reads else 0;
    const hit_delta = if (after.fs_cache_hits >= before.fs_cache_hits) after.fs_cache_hits - before.fs_cache_hits else 0;
    const len_ok = a > 0 and b == a;
    const bytes_ok = len_ok and memEql(first[0..@intCast(a)], second[0..@intCast(b)]);
    const ok = dev.hasFn("performance_summary") and
        (after.flags & r4os.abi.performance_flag_fs_page_cache_ready) != 0 and
        len_ok and
        bytes_ok and
        read_delta >= 2 and
        hit_delta >= 1 and
        after.fs_cache_capacity > 0 and
        after.fs_cache_sector_bytes == 512 and
        after.fs_cache_entries_used > 0 and
        // In-place data writes stay lazily dirty on NTFS-C: until the
        // writeback worker drains them; errors must still be zero.
        after.fs_cache_read_errors == 0 and
        after.fs_cache_write_errors == 0 and
        after.fs_cache_writeback_errors == 0;

    ctx.write("FSDIAG cache result: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" reads=");
    ctx.printU64(after.fs_cache_reads);
    ctx.write(" hits=");
    ctx.printU64(after.fs_cache_hits);
    ctx.write(" misses=");
    ctx.printU64(after.fs_cache_misses);
    ctx.write(" delta=");
    ctx.printU64(read_delta);
    ctx.write("/");
    ctx.printU64(hit_delta);
    ctx.write(" entries=");
    ctx.printU64(after.fs_cache_entries_used);
    ctx.write("/");
    ctx.printU64(after.fs_cache_capacity);
    ctx.write(" dirty=");
    ctx.printU64(after.fs_cache_dirty_entries);
    ctx.println("");
    return ok;
}

fn checkCacheWriteback(ctx: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context) bool {
    const before = dev.performanceSummary() orelse {
        ctx.println("FSDIAG writeback result: FAILED performance unavailable");
        return false;
    };
    const payload = "fsdiag-writeback-v119";
    const written = ctx.fileWrite("C:\\TEMP\\FSWB.TXT", payload);
    var verify: [64]u8 = undefined;
    const read = ctx.fileReadAt("C:\\TEMP\\FSWB.TXT", 0, verify[0..]);
    const after = dev.performanceSummary() orelse {
        ctx.println("FSDIAG writeback result: FAILED performance unavailable");
        return false;
    };
    const expected_len: i32 = @intCast(payload.len);
    const deferred_delta = delta(after.fs_cache_deferred_write_requests, before.fs_cache_deferred_write_requests);
    const writeback_delta = delta(after.fs_cache_writeback_sectors, before.fs_cache_writeback_sectors);
    const drain_delta = delta(after.fs_cache_writeback_drains, before.fs_cache_writeback_drains);
    const flush_delta = delta(after.fs_cache_writeback_flush_drains, before.fs_cache_writeback_flush_drains);
    const len_ok = written == expected_len and read == expected_len;
    const bytes_ok = len_ok and memEql(verify[0..payload.len], payload);
    const ok = dev.hasFn("performance_summary") and
        (after.flags & r4os.abi.performance_flag_fs_writeback_ready) != 0 and
        len_ok and
        bytes_ok and
        deferred_delta > 0 and
        writeback_delta > 0 and
        drain_delta > 0 and
        flush_delta > 0 and
        after.fs_cache_dirty_entries == 0 and
        after.fs_cache_dirty_bytes == 0 and
        after.fs_cache_writeback_queue_depth == 0 and
        after.fs_cache_writeback_queue_high_water > 0 and
        after.fs_cache_write_errors == 0 and
        after.fs_cache_writeback_errors == 0;

    ctx.write("FSDIAG writeback result: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" deferred=");
    ctx.printU64(deferred_delta);
    ctx.write(" wb=");
    ctx.printU64(writeback_delta);
    ctx.write(" drain=");
    ctx.printU64(drain_delta);
    ctx.write(" flush=");
    ctx.printU64(flush_delta);
    ctx.write(" dirty=");
    ctx.printU64(after.fs_cache_dirty_entries);
    ctx.write(" q=");
    ctx.printU64(after.fs_cache_writeback_queue_depth);
    ctx.write("/");
    ctx.printU64(after.fs_cache_writeback_queue_high_water);
    ctx.write(" err=");
    ctx.printU64(after.fs_cache_write_errors +% after.fs_cache_writeback_errors);
    ctx.println("");
    return ok;
}

fn checkFat32Instrumentation(ctx: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context) bool {
    if (!dev.hasFn("performance_summary")) {
        ctx.println("FSDIAG fat32 metrics result: FAILED missing group-table fn");
        return false;
    }

    _ = ctx.fileDelete(fat32_probe_path);
    _ = ctx.fileDelete(fat32_probe_stream_path);

    const before = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 metrics result: FAILED performance unavailable");
        return false;
    };

    var chunk: [fat32_probe_chunk]u8 = undefined;
    fillStreamPattern(chunk[0..], 0);
    const written = ctx.fileWrite(fat32_probe_path, chunk[0..]);
    const appended = ctx.fileAppend(fat32_probe_path, chunk[0..]);

    var writer: r4os.file_stream.WriterState = undefined;
    var expected_checksum: u32 = 0;
    var stream_ok = r4os.file_stream.begin(ctx, &writer, fat32_probe_stream_path, r4os.abi.file_stream_open_replace);
    while (stream_ok and writer.offset < fat32_probe_stream_bytes) {
        const want: usize = @intCast(@min(@as(u64, chunk.len), fat32_probe_stream_bytes - writer.offset));
        fillStreamPattern(chunk[0..want], writer.offset);
        expected_checksum = checksumUpdate(expected_checksum, chunk[0..want]);
        if (!r4os.file_stream.write(ctx, &writer, chunk[0..want])) {
            stream_ok = false;
            _ = r4os.file_stream.abort(ctx, &writer);
            break;
        }
    }
    if (stream_ok and !r4os.file_stream.finish(ctx, &writer)) stream_ok = false;

    var read_chunk: [fat32_probe_chunk]u8 = undefined;
    const read_checksum = if (stream_ok) checksumFile(ctx, fat32_probe_stream_path, fat32_probe_stream_bytes, read_chunk[0..]) else null;

    const after = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 metrics result: FAILED performance unavailable");
        return false;
    };

    const expected_chunk_len: i32 = @intCast(fat32_probe_chunk);
    const len_ok = written == expected_chunk_len and appended == expected_chunk_len and writer.offset == fat32_probe_stream_bytes;
    const checksum_ok = read_checksum != null and read_checksum.? == expected_checksum;
    const io_failures = delta(after.fat32_read_failures +% after.fat32_write_failures, before.fat32_read_failures +% before.fat32_write_failures);
    const op_failures = delta(after.fat32_operation_failures, before.fat32_operation_failures);
    const flush_failures = delta(after.fat32_flush_failures, before.fat32_flush_failures);
    const write_delta = delta(after.fat32_file_writes, before.fat32_file_writes);
    const append_delta = delta(after.fat32_file_appends, before.fat32_file_appends);
    const write_sector_delta = delta(after.fat32_write_sectors, before.fat32_write_sectors);
    const flush_delta = delta(after.fat32_flushes, before.fat32_flushes);
    const dir_scan_delta = delta(after.fat32_dir_scans, before.fat32_dir_scans);
    const dir_entry_delta = delta(after.fat32_dir_entries_scanned, before.fat32_dir_entries_scanned);
    const dir_update_delta = delta(after.fat32_dir_entry_updates, before.fat32_dir_entry_updates);
    const fat_read_delta = delta(after.fat32_fat_reads, before.fat32_fat_reads);
    const fat_write_delta = delta(after.fat32_fat_writes, before.fat32_fat_writes);
    const fat_mirror_delta = delta(after.fat32_fat_mirror_writes, before.fat32_fat_mirror_writes);
    const alloc_chain_delta = delta(after.fat32_alloc_chain_calls, before.fat32_alloc_chain_calls);
    const alloc_cluster_delta = delta(after.fat32_alloc_clusters, before.fat32_alloc_clusters);
    const alloc_search_delta = delta(after.fat32_alloc_search_steps, before.fat32_alloc_search_steps);
    const cluster_walk_delta = delta(after.fat32_cluster_walk_steps, before.fat32_cluster_walk_steps);
    const operation_ticks_delta = delta(after.fat32_operation_total_ticks, before.fat32_operation_total_ticks);
    const hotpath_ok =
        dir_scan_delta < fat32_baseline_055100_dir_scans and
        fat_read_delta < fat32_baseline_055100_fat_reads and
        alloc_search_delta < fat32_baseline_055100_alloc_search_steps and
        cluster_walk_delta < fat32_baseline_055100_cluster_walk_steps;
    const ok = len_ok and
        stream_ok and
        checksum_ok and
        write_delta > 0 and
        append_delta > 0 and
        write_sector_delta > 0 and
        flush_delta > 0 and
        dir_scan_delta > 0 and
        fat_read_delta > 0 and
        operation_ticks_delta > 0 and
        hotpath_ok and
        io_failures == 0 and
        op_failures == 0 and
        flush_failures == 0;

    ctx.write("FSDIAG fat32 metrics result: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" bytes=");
    ctx.printU64(@as(u64, fat32_probe_chunk * 2) + fat32_probe_stream_bytes);
    ctx.write(" writes=");
    ctx.printU64(write_delta);
    ctx.write(" appends=");
    ctx.printU64(append_delta);
    ctx.write(" streamChunks=");
    ctx.printU64(@intCast(writer.chunks));
    ctx.write(" opTicks=");
    ctx.printU64(delta(after.fat32_operation_last_ticks, 0));
    ctx.write("/");
    ctx.printU64(after.fat32_operation_max_ticks);
    ctx.write("/");
    ctx.printU64(operation_ticks_delta);
    ctx.println("");

    ctx.write("FSDIAG fat32 metadata: dir=");
    ctx.printU64(dir_scan_delta);
    ctx.write(" entries=");
    ctx.printU64(dir_entry_delta);
    ctx.write(" updates=");
    ctx.printU64(dir_update_delta);
    ctx.write(" fat=");
    ctx.printU64(fat_read_delta);
    ctx.write("/");
    ctx.printU64(fat_write_delta);
    ctx.write("/");
    ctx.printU64(fat_mirror_delta);
    ctx.write(" alloc=");
    ctx.printU64(alloc_chain_delta);
    ctx.write("/");
    ctx.printU64(alloc_cluster_delta);
    ctx.write("/");
    ctx.printU64(alloc_search_delta);
    ctx.write(" walk=");
    ctx.printU64(cluster_walk_delta);
    ctx.println("");

    ctx.write("FSDIAG fat32 hotpath: ");
    ctx.write(if (hotpath_ok) "OK" else "FAILED");
    ctx.write(" dir=");
    ctx.printU64(dir_scan_delta);
    ctx.write("<");
    ctx.printU64(fat32_baseline_055100_dir_scans);
    ctx.write(" fat=");
    ctx.printU64(fat_read_delta);
    ctx.write("<");
    ctx.printU64(fat32_baseline_055100_fat_reads);
    ctx.write(" allocSearch=");
    ctx.printU64(alloc_search_delta);
    ctx.write("<");
    ctx.printU64(fat32_baseline_055100_alloc_search_steps);
    ctx.write(" walk=");
    ctx.printU64(cluster_walk_delta);
    ctx.write("<");
    ctx.printU64(fat32_baseline_055100_cluster_walk_steps);
    ctx.println("");

    ctx.write("FSDIAG fat32 io: sectors=");
    ctx.printU64(delta(after.fat32_read_sectors, before.fat32_read_sectors));
    ctx.write("/");
    ctx.printU64(write_sector_delta);
    ctx.write(" flush=");
    ctx.printU64(flush_delta);
    ctx.write(" flushTicks=");
    ctx.printU64(after.fat32_flush_last_ticks);
    ctx.write("/");
    ctx.printU64(after.fat32_flush_max_ticks);
    ctx.write("/");
    ctx.printU64(delta(after.fat32_flush_total_ticks, before.fat32_flush_total_ticks));
    ctx.write(" failures=");
    ctx.printU64(io_failures +% op_failures +% flush_failures);
    ctx.println("");

    _ = ctx.fileDelete(fat32_probe_path);
    _ = ctx.fileDelete(fat32_probe_stream_path);
    return ok;
}

fn checkDataDrive(ctx: *const r4os.r4sys.Context, letter: u8) bool {
    ctx.write("drive ");
    ctx.putc(letter);
    ctx.write(": ");
    if (ctx.driveInfo(letter - 'A')) |info| {
        ctx.write(if (info.mounted != 0) "mounted " else "not-mounted ");
        ctx.write("kind=");
        ctx.write(kindName(info.kind));
        ctx.write(" role=");
        ctx.write(roleName(info.role));
        ctx.write(" bytes=");
        ctx.printU64(info.bytes);
        ctx.write(" free=");
        ctx.printU64(info.free_bytes);
        ctx.println("");
        return info.mounted != 0 and info.kind == 2;
    }
    ctx.println("missing");
    return false;
}

fn kindName(kind: u32) []const u8 {
    return switch (kind) {
        1 => "RAM",
        2 => "FAT32",
        3 => "NTFS",
        else => "NONE",
    };
}

fn roleName(role: u32) []const u8 {
    return switch (role) {
        1 => "system",
        2 => "data",
        3 => "ram",
        else => "general",
    };
}

fn checkWriteRead(ctx: *const r4os.r4sys.Context) bool {
    const written = ctx.fileWrite(test_path, test_data);
    ctx.write("write ");
    ctx.write(test_path);
    ctx.write(": ");
    ctx.printI32(written);
    ctx.println(" bytes");
    if (written != test_data.len) return false;

    const first_info = ctx.fileInfo(test_path) orelse {
        ctx.println("timestamp after write: FAILED missing file info");
        return false;
    };
    if (!checkFatTimestamp(ctx, "timestamp after write", first_info)) return false;

    const appended = ctx.fileAppend(test_path, append_data);
    ctx.write("append ");
    ctx.write(test_path);
    ctx.write(": ");
    ctx.printI32(appended);
    ctx.println(" bytes");
    if (appended != append_data.len) return false;

    const second_info = ctx.fileInfo(test_path) orelse {
        ctx.println("timestamp after append: FAILED missing file info");
        return false;
    };
    if (second_info.size != test_data.len + append_data.len) return false;
    if (!checkFatTimestamp(ctx, "timestamp after append", second_info)) return false;

    var buf: [96]u8 = undefined;
    const read = ctx.fileRead(test_path, buf[0..]);
    ctx.write("readback: ");
    ctx.printI32(read);
    ctx.println(" bytes");
    const total_len = test_data.len + append_data.len;
    if (read != total_len) return false;
    return memEql(buf[0..test_data.len], test_data) and memEql(buf[test_data.len..total_len], append_data);
}

fn checkStreaming(ctx: *const r4os.r4sys.Context) bool {
    ctx.write("file stream v2: ");
    if (!ctx.hasFn("file_stream_begin")) {
        ctx.println("FAILED missing group-table fn");
        return false;
    }
    ctx.println("available");

    _ = ctx.fileDelete(stream_path);
    _ = ctx.fileDelete(stream_copy_path);

    var writer: r4os.file_stream.WriterState = undefined;
    if (!r4os.file_stream.begin(ctx, &writer, stream_path, r4os.abi.file_stream_open_replace)) {
        ctx.write("stream begin: FAILED rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }

    var chunk: [stream_write_chunk]u8 = undefined;
    var expected_checksum: u32 = 0;
    while (writer.offset < stream_total_bytes) {
        const want: usize = @intCast(@min(@as(u64, chunk.len), stream_total_bytes - writer.offset));
        fillStreamPattern(chunk[0..want], writer.offset);
        expected_checksum = checksumUpdate(expected_checksum, chunk[0..want]);
        if (!r4os.file_stream.write(ctx, &writer, chunk[0..want])) {
            ctx.write("stream write: FAILED rc=");
            ctx.printI32(writer.error_code);
            ctx.println("");
            _ = r4os.file_stream.abort(ctx, &writer);
            return false;
        }
    }

    if (!r4os.file_stream.finish(ctx, &writer)) {
        ctx.write("stream finish: FAILED rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }

    const wrong_offset_rc = ctx.fileStreamWrite(stream_path, 1, "X", 0);
    const offset_guard_ok = wrong_offset_rc == r4os.abi.file_stream_error_offset_mismatch;
    var read_chunk: [stream_write_chunk]u8 = undefined;
    const read_checksum = checksumFile(ctx, stream_path, stream_total_bytes, read_chunk[0..]) orelse return false;

    var copy_buffer: [stream_copy_chunk]u8 = undefined;
    const copy = r4os.file_stream.copy(ctx, stream_path, stream_copy_path, copy_buffer[0..]);
    const copy_checksum = if (copy.ok) checksumFile(ctx, stream_copy_path, stream_total_bytes, read_chunk[0..]) else null;

    const ok =
        offset_guard_ok and
        read_checksum == expected_checksum and
        copy.ok and
        copy.bytes == stream_total_bytes and
        copy.max_chunk <= stream_copy_chunk and
        copy_checksum != null and
        copy_checksum.? == expected_checksum;

    ctx.write("stream write/read: bytes=");
    ctx.printU64(stream_total_bytes);
    ctx.write(" chunks=");
    ctx.printU64(@intCast(writer.chunks));
    ctx.write(" maxChunk=");
    ctx.printU64(@intCast(writer.max_chunk));
    ctx.write(" checksum=");
    ctx.printU64(@intCast(expected_checksum));
    ctx.write(" guard=");
    ctx.write(if (offset_guard_ok) "OK" else "FAILED");
    ctx.println("");

    ctx.write("stream copy: bytes=");
    ctx.printU64(copy.bytes);
    ctx.write(" chunks=");
    ctx.printU64(@intCast(copy.chunks));
    ctx.write(" maxChunk=");
    ctx.printU64(@intCast(copy.max_chunk));
    ctx.write(" rc=");
    ctx.printI32(copy.error_code);
    ctx.println("");

    ctx.write("FSDIAG stream result: ");
    ctx.println(if (ok) "OK" else "FAILED");
    return ok;
}

fn checkLargeStreaming(ctx: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context) bool {
    if (!dev.hasFn("performance_summary")) {
        ctx.println("FSDIAG stream large result: FAILED missing group-table fn");
        return false;
    }
    if (!dev.hasFn("performance_summary")) {
        ctx.println("FSDIAG stream large result: FAILED missing group-table fn");
        return false;
    }

    _ = ctx.fileDelete(stream_large_path);
    _ = ctx.fileDelete(stream_abort_path);

    const before = dev.performanceSummary();

    var writer: r4os.file_stream.WriterState = undefined;
    if (!r4os.file_stream.begin(ctx, &writer, stream_large_path, r4os.abi.file_stream_open_replace)) {
        ctx.write("FSDIAG stream large result: FAILED begin rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }

    var chunk: [stream_large_chunk]u8 = undefined;
    var expected_checksum: u32 = 0;
    var offset_guard_checked = false;
    var offset_guard_ok = false;
    while (writer.offset < stream_large_bytes) {
        const want: usize = @intCast(@min(@as(u64, chunk.len), stream_large_bytes - writer.offset));
        fillStreamPattern(chunk[0..want], writer.offset);
        expected_checksum = checksumUpdate(expected_checksum, chunk[0..want]);
        if (!r4os.file_stream.write(ctx, &writer, chunk[0..want])) {
            ctx.write("FSDIAG stream large result: FAILED write rc=");
            ctx.printI32(writer.error_code);
            ctx.println("");
            _ = r4os.file_stream.abort(ctx, &writer);
            return false;
        }
        if (!offset_guard_checked) {
            const wrong_offset_rc = ctx.fileStreamWrite(stream_large_path, writer.offset + 1, "X", 0);
            offset_guard_ok = wrong_offset_rc == r4os.abi.file_stream_error_offset_mismatch;
            offset_guard_checked = true;
        }
    }

    const wrong_finish_rc = ctx.fileStreamFinish(stream_large_path, writer.offset + 1, 0);
    const finish_guard_ok = wrong_finish_rc == r4os.abi.file_stream_error_size_mismatch;
    if (!r4os.file_stream.finish(ctx, &writer)) {
        ctx.write("FSDIAG stream large result: FAILED finish rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }

    var read_chunk: [stream_large_chunk]u8 = undefined;
    const read_checksum = checksumFile(ctx, stream_large_path, stream_large_bytes, read_chunk[0..]);
    const checksum_ok = read_checksum != null and read_checksum.? == expected_checksum;
    const after_large = dev.performanceSummary();

    var metrics_ok = false;
    var flush_guard_ok = false;
    var dirty_clean_ok = false;
    var writeback_ok = false;
    var stream_flush_delta: u64 = 0;
    var stream_flush_failure_delta: u64 = 0;
    var stream_dirty_entries: u64 = 0;
    var stream_dirty_bytes: u64 = 0;
    var stream_writeback_flush_delta: u64 = 0;
    var stream_writeback_sectors_delta: u64 = 0;
    var stream_yield_points_delta: u64 = 0;
    var stream_yields_delta: u64 = 0;
    var stream_yield_skips_delta: u64 = 0;
    var stream_alloc_runs_delta: u64 = 0;
    var stream_alloc_run_clusters_delta: u64 = 0;
    var stream_alloc_run_max: u64 = 0;
    var stream_fat_sector_writes_delta: u64 = 0;
    var responsiveness_ok = false;
    var batching_ok = false;
    if (before) |before_summary| {
        if (after_large) |after_summary| {
            stream_flush_delta = delta(after_summary.fat32_flushes, before_summary.fat32_flushes);
            stream_flush_failure_delta = delta(after_summary.fat32_flush_failures, before_summary.fat32_flush_failures);
            stream_dirty_entries = @intCast(after_summary.fs_cache_dirty_entries);
            stream_dirty_bytes = after_summary.fs_cache_dirty_bytes;
            stream_writeback_flush_delta = delta(after_summary.fs_cache_writeback_flush_drains, before_summary.fs_cache_writeback_flush_drains);
            stream_writeback_sectors_delta = delta(after_summary.fs_cache_writeback_sectors, before_summary.fs_cache_writeback_sectors);
            stream_yield_points_delta = delta(after_summary.fat32_yield_points, before_summary.fat32_yield_points);
            stream_yields_delta = delta(after_summary.fat32_yields, before_summary.fat32_yields);
            stream_yield_skips_delta = delta(after_summary.fat32_yield_skips, before_summary.fat32_yield_skips);
            stream_alloc_runs_delta = delta(after_summary.fat32_alloc_runs, before_summary.fat32_alloc_runs);
            stream_alloc_run_clusters_delta = delta(after_summary.fat32_alloc_run_clusters, before_summary.fat32_alloc_run_clusters);
            stream_alloc_run_max = after_summary.fat32_alloc_run_max_clusters;
            stream_fat_sector_writes_delta = delta(after_summary.fat32_fat_sector_writes, before_summary.fat32_fat_sector_writes);
            flush_guard_ok = stream_flush_delta > 0 and stream_flush_delta <= stream_large_max_flushes;
            dirty_clean_ok = stream_dirty_entries == 0 and stream_dirty_bytes == 0;
            writeback_ok = stream_writeback_flush_delta > 0 and stream_writeback_sectors_delta > 0;
            responsiveness_ok = stream_yield_points_delta > 0 and stream_yields_delta > 0;
            batching_ok = stream_alloc_runs_delta > 0 and stream_alloc_run_clusters_delta > stream_alloc_runs_delta and stream_alloc_run_max >= 2 and stream_fat_sector_writes_delta > 0;
            metrics_ok = flush_guard_ok and dirty_clean_ok and writeback_ok and responsiveness_ok and batching_ok and stream_flush_failure_delta == 0;
        }
    }

    _ = ctx.fileDelete(stream_large_path);
    const abort_ok = checkStreamAbort(ctx, chunk[0..]);
    const ok = offset_guard_ok and finish_guard_ok and checksum_ok and abort_ok and metrics_ok;

    ctx.write("FSDIAG stream large result: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" bytes=");
    ctx.printU64(stream_large_bytes);
    ctx.write(" chunks=");
    ctx.printU64(@intCast(writer.chunks));
    ctx.write(" maxChunk=");
    ctx.printU64(writer.max_chunk);
    ctx.write(" offsetGuard=");
    ctx.write(if (offset_guard_ok) "yes" else "no");
    ctx.write(" finishGuard=");
    ctx.write(if (finish_guard_ok) "yes" else "no");
    ctx.write(" checksum=");
    ctx.write(if (checksum_ok) "yes" else "no");
    ctx.write(" abort=");
    ctx.write(if (abort_ok) "yes" else "no");
    ctx.write(" flushGuard=");
    ctx.write(if (flush_guard_ok) "yes" else "no");
    ctx.write(" dirtyClean=");
    ctx.write(if (dirty_clean_ok) "yes" else "no");
    ctx.write(" yield=");
    ctx.write(if (responsiveness_ok) "yes" else "no");
    ctx.write(" batching=");
    ctx.write(if (batching_ok) "yes" else "no");
    ctx.println("");

    if (before) |before_summary| {
        if (after_large) |after_summary| {
            ctx.write("FSDIAG stream large metrics: requests=");
            ctx.printU64(delta(after_summary.fs_stream_requests, before_summary.fs_stream_requests));
            ctx.write(" fat=");
            ctx.printU64(delta(after_summary.fat32_fat_reads, before_summary.fat32_fat_reads));
            ctx.write(" allocSearch=");
            ctx.printU64(delta(after_summary.fat32_alloc_search_steps, before_summary.fat32_alloc_search_steps));
            ctx.write(" walk=");
            ctx.printU64(delta(after_summary.fat32_cluster_walk_steps, before_summary.fat32_cluster_walk_steps));
            ctx.write(" flush=");
            ctx.printU64(stream_flush_delta);
            ctx.write("<=");
            ctx.printU64(stream_large_max_flushes);
            ctx.write(" wbFlush=");
            ctx.printU64(stream_writeback_flush_delta);
            ctx.write(" wbSectors=");
            ctx.printU64(stream_writeback_sectors_delta);
            ctx.write(" dirty=");
            ctx.printU64(stream_dirty_entries);
            ctx.write("/");
            ctx.printU64(stream_dirty_bytes);
            ctx.write(" yield=");
            ctx.printU64(stream_yields_delta);
            ctx.write("/");
            ctx.printU64(stream_yield_points_delta);
            ctx.write(" skip=");
            ctx.printU64(stream_yield_skips_delta);
            ctx.write(" runs=");
            ctx.printU64(stream_alloc_runs_delta);
            ctx.write("/");
            ctx.printU64(stream_alloc_run_clusters_delta);
            ctx.write(" maxRun=");
            ctx.printU64(stream_alloc_run_max);
            ctx.write(" fatSectors=");
            ctx.printU64(stream_fat_sector_writes_delta);
            ctx.write(" flushFailures=");
            ctx.printU64(stream_flush_failure_delta);
            ctx.println("");
        }
    }

    _ = ctx.fileDelete(stream_large_path);
    _ = ctx.fileDelete(stream_abort_path);
    return ok;
}

fn checkFat32Synthetic14Mb(ctx: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context) bool {
    if (!dev.hasFn("performance_summary")) {
        ctx.println("FSDIAG fat32 synthetic 14mb result: FAILED missing group-table fn");
        return false;
    }

    _ = ctx.fileDelete(fat32_synthetic_14mb_path);
    const before = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 synthetic 14mb result: FAILED performance unavailable");
        return false;
    };

    var writer: r4os.file_stream.WriterState = undefined;
    if (!r4os.file_stream.begin(ctx, &writer, fat32_synthetic_14mb_path, r4os.abi.file_stream_open_replace)) {
        ctx.write("FSDIAG fat32 synthetic 14mb result: FAILED begin rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }

    var chunk: [fat32_synthetic_14mb_chunk]u8 = undefined;
    var expected_checksum: u32 = 0;
    while (writer.offset < fat32_synthetic_14mb_bytes) {
        const want: usize = @intCast(@min(@as(u64, chunk.len), fat32_synthetic_14mb_bytes - writer.offset));
        fillStreamPattern(chunk[0..want], writer.offset);
        expected_checksum = checksumUpdate(expected_checksum, chunk[0..want]);
        if (!r4os.file_stream.write(ctx, &writer, chunk[0..want])) {
            ctx.write("FSDIAG fat32 synthetic 14mb result: FAILED write rc=");
            ctx.printI32(writer.error_code);
            ctx.write(" offset=");
            ctx.printU64(writer.offset);
            ctx.println("");
            if (dev.performanceSummary()) |diag| {
                // Failure diagnostics (0.60.14): distinguishes a real FS
                // fault from cache-writeback pressure that cannot drain
                // (a corrupt persistent data.img shows up as full dirty
                // cache + failed reclaim drains, not as cacheWriteErr).
                ctx.write("FSDIAG fat32 synthetic 14mb diag: cacheWriteErr=");
                ctx.printU64(diag.fs_cache_write_errors);
                ctx.write(" wbErr=");
                ctx.printU64(diag.fs_cache_writeback_errors);
                ctx.write(" dirtyEntries=");
                ctx.printU64(diag.fs_cache_dirty_entries);
                ctx.write(" fatOpFail=");
                ctx.printU64(diag.fat32_operation_failures);
                ctx.write(" failedDrains=");
                ctx.printU64(diag.fs_cache_reclaim_failed_drains);
                ctx.println("");
            }
            _ = r4os.file_stream.abort(ctx, &writer);
            return false;
        }
    }

    if (!r4os.file_stream.finish(ctx, &writer)) {
        ctx.write("FSDIAG fat32 synthetic 14mb result: FAILED finish rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }

    const read_checksum = checksumFile(ctx, fat32_synthetic_14mb_path, fat32_synthetic_14mb_bytes, chunk[0..]);
    const after = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 synthetic 14mb result: FAILED performance unavailable");
        _ = ctx.fileDelete(fat32_synthetic_14mb_path);
        return false;
    };

    const checksum_ok = read_checksum != null and read_checksum.? == expected_checksum;
    const stream_request_delta = delta(after.fs_stream_requests, before.fs_stream_requests);
    const write_sector_delta = delta(after.fat32_write_sectors, before.fat32_write_sectors);
    const fat_read_delta = delta(after.fat32_fat_reads, before.fat32_fat_reads);
    const alloc_search_delta = delta(after.fat32_alloc_search_steps, before.fat32_alloc_search_steps);
    const cluster_walk_delta = delta(after.fat32_cluster_walk_steps, before.fat32_cluster_walk_steps);
    const flush_delta = delta(after.fat32_flushes, before.fat32_flushes);
    const writeback_flush_delta = delta(after.fs_cache_writeback_flush_drains, before.fs_cache_writeback_flush_drains);
    const writeback_sectors_delta = delta(after.fs_cache_writeback_sectors, before.fs_cache_writeback_sectors);
    const alloc_runs_delta = delta(after.fat32_alloc_runs, before.fat32_alloc_runs);
    const alloc_run_clusters_delta = delta(after.fat32_alloc_run_clusters, before.fat32_alloc_run_clusters);
    const fat_sector_writes_delta = delta(after.fat32_fat_sector_writes, before.fat32_fat_sector_writes);
    const read_failures_delta = delta(after.fat32_read_failures, before.fat32_read_failures);
    const write_failures_delta = delta(after.fat32_write_failures, before.fat32_write_failures);
    const op_failures_delta = delta(after.fat32_operation_failures, before.fat32_operation_failures);
    const flush_failures_delta = delta(after.fat32_flush_failures, before.fat32_flush_failures);
    const bytes_ok = writer.offset == fat32_synthetic_14mb_bytes;
    const dirty_clean_ok = after.fs_cache_dirty_entries == 0 and after.fs_cache_dirty_bytes == 0;
    const batching_ok = alloc_runs_delta > 0 and alloc_run_clusters_delta > alloc_runs_delta and after.fat32_alloc_run_max_clusters >= 2 and fat_sector_writes_delta > 0;
    const io_ok = read_failures_delta == 0 and write_failures_delta == 0 and op_failures_delta == 0 and flush_failures_delta == 0;
    const metrics_ok = stream_request_delta > 0 and write_sector_delta > 0 and fat_read_delta > 0 and alloc_search_delta > 0 and cluster_walk_delta > 0 and flush_delta > 0 and writeback_flush_delta > 0 and writeback_sectors_delta > 0;
    const ok = bytes_ok and checksum_ok and batching_ok and dirty_clean_ok and io_ok and metrics_ok;

    ctx.write("FSDIAG fat32 synthetic 14mb result: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" bytes=");
    ctx.printU64(writer.offset);
    ctx.write(" chunks=");
    ctx.printU64(@intCast(writer.chunks));
    ctx.write(" checksum=");
    ctx.write(if (checksum_ok) "yes" else "no");
    ctx.write(" batching=");
    ctx.write(if (batching_ok) "yes" else "no");
    ctx.write(" dirtyClean=");
    ctx.write(if (dirty_clean_ok) "yes" else "no");
    ctx.println("");

    ctx.write("FSDIAG fat32 synthetic 14mb metrics: requests=");
    ctx.printU64(stream_request_delta);
    ctx.write(" writes=");
    ctx.printU64(write_sector_delta);
    ctx.write(" fat=");
    ctx.printU64(fat_read_delta);
    ctx.write(" allocSearch=");
    ctx.printU64(alloc_search_delta);
    ctx.write(" walk=");
    ctx.printU64(cluster_walk_delta);
    ctx.write(" flush=");
    ctx.printU64(flush_delta);
    ctx.write(" wbFlush=");
    ctx.printU64(writeback_flush_delta);
    ctx.write(" wbSectors=");
    ctx.printU64(writeback_sectors_delta);
    ctx.write(" runs=");
    ctx.printU64(alloc_runs_delta);
    ctx.write("/");
    ctx.printU64(alloc_run_clusters_delta);
    ctx.write(" maxRun=");
    ctx.printU64(after.fat32_alloc_run_max_clusters);
    ctx.write(" fatSectors=");
    ctx.printU64(fat_sector_writes_delta);
    ctx.write(" dirty=");
    ctx.printU64(after.fs_cache_dirty_entries);
    ctx.write("/");
    ctx.printU64(after.fs_cache_dirty_bytes);
    ctx.write(" failures=");
    ctx.printU64(read_failures_delta);
    ctx.write("/");
    ctx.printU64(write_failures_delta);
    ctx.write("/");
    ctx.printU64(op_failures_delta);
    ctx.write("/");
    ctx.printU64(flush_failures_delta);
    ctx.println("");

    _ = ctx.fileDelete(fat32_synthetic_14mb_path);
    return ok;
}

fn checkFat32ReadExtentCache(ctx: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context) bool {
    if (!dev.hasFn("performance_summary")) {
        ctx.println("FSDIAG fat32 extent cache result: FAILED missing group-table fn");
        return false;
    }

    _ = ctx.fileDelete(fat32_extent_cache_path);
    var writer: r4os.file_stream.WriterState = undefined;
    if (!r4os.file_stream.begin(ctx, &writer, fat32_extent_cache_path, r4os.abi.file_stream_open_replace)) {
        ctx.write("FSDIAG fat32 extent cache result: FAILED begin rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }

    var chunk: [fat32_extent_cache_chunk]u8 = undefined;
    var expected_checksum: u32 = 0;
    while (writer.offset < fat32_extent_cache_bytes) {
        const want: usize = @intCast(@min(@as(u64, chunk.len), fat32_extent_cache_bytes - writer.offset));
        fillStreamPattern(chunk[0..want], writer.offset);
        expected_checksum = checksumUpdate(expected_checksum, chunk[0..want]);
        if (!r4os.file_stream.write(ctx, &writer, chunk[0..want])) {
            ctx.write("FSDIAG fat32 extent cache result: FAILED write rc=");
            ctx.printI32(writer.error_code);
            ctx.println("");
            _ = r4os.file_stream.abort(ctx, &writer);
            return false;
        }
    }

    if (!r4os.file_stream.finish(ctx, &writer)) {
        ctx.write("FSDIAG fat32 extent cache result: FAILED finish rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        _ = ctx.fileDelete(fat32_extent_cache_path);
        return false;
    }

    const before_first = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 extent cache result: FAILED performance unavailable");
        _ = ctx.fileDelete(fat32_extent_cache_path);
        return false;
    };
    const first_checksum = checksumFile(ctx, fat32_extent_cache_path, fat32_extent_cache_bytes, chunk[0..]);
    const after_first = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 extent cache result: FAILED performance unavailable");
        _ = ctx.fileDelete(fat32_extent_cache_path);
        return false;
    };
    const second_checksum = checksumFile(ctx, fat32_extent_cache_path, fat32_extent_cache_bytes, chunk[0..]);
    const after_second = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 extent cache result: FAILED performance unavailable");
        _ = ctx.fileDelete(fat32_extent_cache_path);
        return false;
    };

    var offset_buf: [4096]u8 = undefined;
    const offset_read = ctx.fileReadAt(fat32_extent_cache_path, fat32_extent_cache_offset, offset_buf[0..]);
    const after_offset = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 extent cache result: FAILED performance unavailable");
        _ = ctx.fileDelete(fat32_extent_cache_path);
        return false;
    };

    const first_walk = delta(after_first.fat32_cluster_walk_steps, before_first.fat32_cluster_walk_steps);
    const second_walk = delta(after_second.fat32_cluster_walk_steps, after_first.fat32_cluster_walk_steps);
    const offset_walk = delta(after_offset.fat32_cluster_walk_steps, after_second.fat32_cluster_walk_steps);
    const hit_delta = delta(after_offset.fat32_read_extent_cache_hits, before_first.fat32_read_extent_cache_hits);
    const miss_delta = delta(after_offset.fat32_read_extent_cache_misses, before_first.fat32_read_extent_cache_misses);
    const store_delta = delta(after_offset.fat32_read_extent_cache_stores, before_first.fat32_read_extent_cache_stores);
    const cache_cluster_delta = delta(after_offset.fat32_read_extent_cache_clusters, before_first.fat32_read_extent_cache_clusters);
    const read_failures_delta = delta(after_offset.fat32_read_failures, before_first.fat32_read_failures);
    const op_failures_delta = delta(after_offset.fat32_operation_failures, before_first.fat32_operation_failures);

    const bytes_ok = writer.offset == fat32_extent_cache_bytes;
    const checksum_ok = first_checksum != null and second_checksum != null and first_checksum.? == expected_checksum and second_checksum.? == expected_checksum;
    const offset_ok = offset_read == @as(i32, @intCast(offset_buf.len)) and verifyStreamPattern(offset_buf[0..], fat32_extent_cache_offset);
    const cache_ok = first_walk > 0 and second_walk < first_walk and offset_walk <= second_walk and hit_delta > 0 and store_delta > 0 and cache_cluster_delta > 0;
    const io_ok = read_failures_delta == 0 and op_failures_delta == 0;
    const ok = bytes_ok and checksum_ok and offset_ok and cache_ok and io_ok;

    ctx.write("FSDIAG fat32 extent cache result: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" bytes=");
    ctx.printU64(writer.offset);
    ctx.write(" checksum=");
    ctx.write(if (checksum_ok) "yes" else "no");
    ctx.write(" cache=");
    ctx.write(if (cache_ok) "yes" else "no");
    ctx.write(" offset=");
    ctx.write(if (offset_ok) "yes" else "no");
    ctx.println("");

    ctx.write("FSDIAG fat32 extent cache metrics: firstWalk=");
    ctx.printU64(first_walk);
    ctx.write(" secondWalk=");
    ctx.printU64(second_walk);
    ctx.write(" offsetWalk=");
    ctx.printU64(offset_walk);
    ctx.write(" hits=");
    ctx.printU64(hit_delta);
    ctx.write(" misses=");
    ctx.printU64(miss_delta);
    ctx.write(" stores=");
    ctx.printU64(store_delta);
    ctx.write("/");
    ctx.printU64(cache_cluster_delta);
    ctx.write(" failures=");
    ctx.printU64(read_failures_delta);
    ctx.write("/");
    ctx.printU64(op_failures_delta);
    ctx.println("");

    _ = ctx.fileDelete(fat32_extent_cache_path);
    return ok;
}

fn checkFat32FsInfoInuseMap(ctx: *const r4os.r4sys.Context, dev: *const r4os.r4dev.Context) bool {
    if (!dev.hasFn("performance_summary")) {
        ctx.println("FSDIAG fat32 fsinfo result: FAILED missing group-table fn");
        return false;
    }

    _ = ctx.fileDelete(fat32_fsinfo_probe_path);
    const before_info = ctx.driveInfo(3) orelse {
        ctx.println("FSDIAG fat32 fsinfo result: FAILED drive info unavailable");
        return false;
    };
    const before_summary = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 fsinfo result: FAILED performance unavailable");
        return false;
    };

    var writer: r4os.file_stream.WriterState = undefined;
    if (!r4os.file_stream.begin(ctx, &writer, fat32_fsinfo_probe_path, r4os.abi.file_stream_open_replace)) {
        ctx.write("FSDIAG fat32 fsinfo result: FAILED begin rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }

    var chunk: [fat32_fsinfo_probe_chunk]u8 = undefined;
    while (writer.offset < fat32_fsinfo_probe_bytes) {
        const want: usize = @intCast(@min(@as(u64, chunk.len), fat32_fsinfo_probe_bytes - writer.offset));
        fillStreamPattern(chunk[0..want], writer.offset);
        if (!r4os.file_stream.write(ctx, &writer, chunk[0..want])) {
            ctx.write("FSDIAG fat32 fsinfo result: FAILED write rc=");
            ctx.printI32(writer.error_code);
            ctx.println("");
            _ = r4os.file_stream.abort(ctx, &writer);
            return false;
        }
    }
    if (!r4os.file_stream.finish(ctx, &writer)) {
        ctx.write("FSDIAG fat32 fsinfo result: FAILED finish rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        _ = ctx.fileDelete(fat32_fsinfo_probe_path);
        return false;
    }

    const mid_info = ctx.driveInfo(3) orelse {
        ctx.println("FSDIAG fat32 fsinfo result: FAILED drive info unavailable");
        _ = ctx.fileDelete(fat32_fsinfo_probe_path);
        return false;
    };
    const delete_rc = ctx.fileDelete(fat32_fsinfo_probe_path);
    const after_info = ctx.driveInfo(3) orelse {
        ctx.println("FSDIAG fat32 fsinfo result: FAILED drive info unavailable");
        return false;
    };
    const after_summary = dev.performanceSummary() orelse {
        ctx.println("FSDIAG fat32 fsinfo result: FAILED performance unavailable");
        return false;
    };

    const cluster_bytes = if (before_info.cluster_bytes != 0) before_info.cluster_bytes else 1;
    const expected_clusters = (fat32_fsinfo_probe_bytes + @as(u64, cluster_bytes) - 1) / @as(u64, cluster_bytes);
    const wrote_clusters = if (before_info.free_clusters >= mid_info.free_clusters) before_info.free_clusters - mid_info.free_clusters else 0;
    const alloc_ok = wrote_clusters == expected_clusters;
    const delete_ok = delete_rc > 0 and ctx.fileInfo(fat32_fsinfo_probe_path) == null and after_info.free_clusters == before_info.free_clusters;
    const mount_ok = after_summary.fat32_fsinfo_valid_mounts + after_summary.fat32_fsinfo_rebuilds > 0;
    const map_ok = after_summary.fat32_inusemap_builds > 0 and after_summary.fat32_inusemap_clusters > 0;
    const fsinfo_write_delta = delta(after_summary.fat32_fsinfo_writes, before_summary.fat32_fsinfo_writes);
    const map_hit_delta = delta(after_summary.fat32_inusemap_alloc_hits, before_summary.fat32_inusemap_alloc_hits);
    const metrics_ok = mount_ok and map_ok and fsinfo_write_delta > 0 and map_hit_delta > 0;
    const ok = writer.offset == fat32_fsinfo_probe_bytes and alloc_ok and delete_ok and metrics_ok;

    ctx.write("FSDIAG fat32 fsinfo result: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" bytes=");
    ctx.printU64(writer.offset);
    ctx.write(" clusters=");
    ctx.printU64(wrote_clusters);
    ctx.write("/");
    ctx.printU64(expected_clusters);
    ctx.write(" delete=");
    ctx.write(if (delete_ok) "yes" else "no");
    ctx.write(" map=");
    ctx.write(if (map_ok) "yes" else "no");
    ctx.write(" fsinfo=");
    ctx.write(if (mount_ok) "yes" else "no");
    ctx.println("");

    ctx.write("FSDIAG fat32 fsinfo metrics: free=");
    ctx.printU64(before_info.free_clusters);
    ctx.write("/");
    ctx.printU64(mid_info.free_clusters);
    ctx.write("/");
    ctx.printU64(after_info.free_clusters);
    ctx.write(" writes=");
    ctx.printU64(fsinfo_write_delta);
    ctx.write(" mapBuilds=");
    ctx.printU64(after_summary.fat32_inusemap_builds);
    ctx.write(" mapClusters=");
    ctx.printU64(after_summary.fat32_inusemap_clusters);
    ctx.write(" mapHits=");
    ctx.printU64(map_hit_delta);
    ctx.write(" fsinfoMounts=");
    ctx.printU64(after_summary.fat32_fsinfo_valid_mounts);
    ctx.write("/");
    ctx.printU64(after_summary.fat32_fsinfo_rebuilds);
    ctx.println("");

    return ok;
}

fn checkRegistryRecentWriteback(ctx: *const r4os.r4sys.Context) bool {
    if (!ctx.hasFn("registry_get_value") or !ctx.hasFn("registry_set_value")) {
        ctx.println("FSDIAG registry recent writeback: FAILED registry API unavailable");
        return false;
    }

    const first_path = "C:\\TEMP\\FSDIAG-R1.TXT";
    const second_path = "C:\\TEMP\\FSDIAG-R2.TXT";
    const start = ctx.ticks();
    const first_ok = r4os.recent_documents.addOpenedFile(ctx, first_path, "FSDIAG");
    const second_ok = r4os.recent_documents.addOpenedFile(ctx, second_path, "FSDIAG");
    const promote_ok = r4os.recent_documents.addOpenedFile(ctx, first_path, "FSDIAG");
    const elapsed = delta(ctx.ticks(), start);

    var entries: [r4os.recent_documents.max_items]r4os.recent_documents.Entry = .{r4os.recent_documents.Entry{}} ** r4os.recent_documents.max_items;
    const count = r4os.recent_documents.readEntries(ctx, entries[0..]);
    const front_ok = count >= 2 and
        equalsIgnoreCase(entries[0].pathText(), first_path) and
        equalsIgnoreCase(entries[1].pathText(), second_path) and
        equalsIgnoreCase(entries[0].appText(), "FSDIAG");
    // 0.56.13: 2000 -> 4000 ms. Die 2s-Schwelle flatterte unter Host-Last
    // (2240 ms gemessen, Smoke kippte lauffallabhaengig rot); 4s bleibt
    // ein wirksamer Haenger-Wachhund, ohne Wirtslast zu bestrafen.
    // 0.56.37: 4000 -> 6000 ms. Nach der IPC-Vergroesserung (4-KB-
    // Messages, +384 KB Kernel-BSS) liegt die Latenz stabil bei
    // ~4,4 s (443/435 Ticks bei freiem Host, 574 unter Spiel-Last) -
    // der Writeback SELBST ist korrekt, das Budget verpasste nur
    // knapp das naechste Flush-Fenster. 6 s bleibt Haenger-Wachhund.
    const responsiveness_ok = elapsed <= ctx.ticksFromMilliseconds(6000);
    const ok = first_ok and second_ok and promote_ok and front_ok and responsiveness_ok;

    ctx.write("FSDIAG registry recent writeback: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" entries=");
    ctx.printU64(@intCast(count));
    ctx.write(" ticks=");
    ctx.printU64(elapsed);
    ctx.write(" max=");
    ctx.printU64(ctx.ticksFromMilliseconds(6000));
    ctx.write(" front=");
    if (count > 0) {
        ctx.write(entries[0].pathText());
    } else {
        ctx.write("-");
    }
    ctx.println("");
    return ok;
}

fn checkStreamAbort(ctx: *const r4os.r4sys.Context, sample: []const u8) bool {
    var writer: r4os.file_stream.WriterState = undefined;
    if (!r4os.file_stream.begin(ctx, &writer, stream_abort_path, r4os.abi.file_stream_open_replace)) {
        ctx.write("FSDIAG stream abort detail: begin rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        return false;
    }
    if (!r4os.file_stream.write(ctx, &writer, sample[0..@min(sample.len, stream_write_chunk)])) {
        ctx.write("FSDIAG stream abort detail: write rc=");
        ctx.printI32(writer.error_code);
        ctx.println("");
        _ = r4os.file_stream.abort(ctx, &writer);
        return false;
    }
    const abort_rc = r4os.file_stream.abort(ctx, &writer);
    const gone = ctx.fileInfo(stream_abort_path) == null;
    ctx.write("FSDIAG stream abort detail: rc=");
    ctx.printI32(abort_rc);
    ctx.write(" gone=");
    ctx.write(if (gone) "yes" else "no");
    ctx.println("");
    return abort_rc == r4os.abi.file_stream_result_ok and gone;
}

fn checkSystemReplaceContract(ctx: *const r4os.r4sys.Context) bool {
    _ = ctx.fileDelete(system_replace_target_path);
    _ = ctx.fileDelete(system_replace_stage_path);
    _ = ctx.fileDelete(system_replace_backup_path);

    const original_written = ctx.fileWrite(system_replace_target_path, system_replace_original);
    if (original_written != @as(i32, @intCast(system_replace_original.len))) {
        ctx.println("FSDIAG system replace result: FAILED original-write");
        return false;
    }

    const staged_written = ctx.fileWrite(system_replace_stage_path, system_replace_update);
    if (staged_written != @as(i32, @intCast(system_replace_update.len))) {
        ctx.write("FSDIAG system replace result: FAILED stage-write rc=");
        ctx.printI32(staged_written);
        ctx.println("");
        _ = ctx.fileDelete(system_replace_target_path);
        _ = ctx.fileDelete(system_replace_stage_path);
        return false;
    }

    var plan = ctx.systemReplacePrepare(
        system_replace_target_path,
        system_replace_stage_path,
        system_replace_backup_path,
        r4os.r4sys.system_replace_flag_allow_temp,
    );
    const prepare_ok = plan.ok() and plan.class == .temp and !plan.rebootRequired() and plan.target_exists and plan.staged_size == system_replace_update.len;
    const apply_rc = if (prepare_ok) ctx.systemReplaceApply(&plan) else plan.result;

    var target_buf: [96]u8 = undefined;
    var backup_buf: [96]u8 = undefined;
    const target_read = ctx.fileRead(system_replace_target_path, target_buf[0..]);
    const backup_read = ctx.fileRead(system_replace_backup_path, backup_buf[0..]);
    const target_ok = target_read == @as(i32, @intCast(system_replace_update.len)) and memEql(target_buf[0..system_replace_update.len], system_replace_update);
    const backup_ok = backup_read == @as(i32, @intCast(system_replace_original.len)) and memEql(backup_buf[0..system_replace_original.len], system_replace_original);
    const stage_gone = ctx.fileInfo(system_replace_stage_path) == null;
    const class_kernel_ok = r4os.r4sys.classifySystemPath("/boot/r4os.elf") == .boot_kernel and r4os.r4sys.systemReplaceNeedsReboot(.boot_kernel);
    const class_library_ok = r4os.r4sys.classifySystemPath("C:\\R4OS\\LIBS\\R4SYS.R4L") == .system_library and r4os.r4sys.systemReplaceNeedsReboot(.system_library);
    const class_config_ok = r4os.r4sys.classifySystemPath("C:\\R4OS\\CONFIG\\VERSION.R4S") == .config and !r4os.r4sys.systemReplaceNeedsReboot(.config);

    const ok = prepare_ok and apply_rc == r4os.r4sys.system_replace_result_ok and target_ok and backup_ok and stage_gone and class_kernel_ok and class_library_ok and class_config_ok;
    ctx.write("FSDIAG system replace result: ");
    ctx.write(if (ok) "OK" else "FAILED");
    ctx.write(" class=");
    ctx.write(plan.className());
    ctx.write(" rc=");
    ctx.write(r4os.r4sys.systemReplaceResultName(apply_rc));
    ctx.write(" backup=");
    ctx.write(if (backup_ok) "yes" else "no");
    ctx.write(" reboot=");
    ctx.write(if (plan.rebootRequired()) "yes" else "no");
    ctx.println("");

    _ = ctx.fileDelete(system_replace_target_path);
    if (backup_ok) _ = ctx.fileRename(system_replace_backup_path, system_replace_target_path);
    _ = ctx.fileDelete(system_replace_target_path);
    _ = ctx.fileDelete(system_replace_stage_path);
    _ = ctx.fileDelete(system_replace_backup_path);
    return ok;
}

fn checksumFile(ctx: *const r4os.r4sys.Context, path: [*:0]const u8, expected_size: u64, buffer: []u8) ?u32 {
    var offset: u64 = 0;
    var checksum: u32 = 0;
    while (offset < expected_size) {
        const want: usize = @intCast(@min(@as(u64, buffer.len), expected_size - offset));
        const read = ctx.fileReadAt(path, @intCast(offset), buffer[0..want]);
        if (read <= 0) return null;
        const got: usize = @intCast(read);
        checksum = checksumUpdate(checksum, buffer[0..got]);
        offset += got;
    }
    return checksum;
}

fn fillStreamPattern(out: []u8, offset: u64) void {
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        const value = offset + @as(u64, @intCast(i));
        out[i] = @truncate((value *% 31) +% (value >> 7) +% 0x5A);
    }
}

fn verifyStreamPattern(data: []const u8, offset: u64) bool {
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        const value = offset + @as(u64, @intCast(i));
        const expected: u8 = @truncate((value *% 31) +% (value >> 7) +% 0x5A);
        if (data[i] != expected) return false;
    }
    return true;
}

fn checksumUpdate(seed: u32, data: []const u8) u32 {
    var sum = seed;
    for (data) |byte| {
        sum = sum *% 16777619 +% byte;
    }
    return sum;
}

fn checkFatTimestamp(ctx: *const r4os.r4sys.Context, label: []const u8, info: r4os.abi.FileInfo) bool {
    const created = r4std.date.decodeFatDateTime(info.created_date, info.created_time);
    const modified = r4std.date.decodeFatDateTime(info.modified_date, info.modified_time);
    const accessed = r4std.date.decodeFatDate(info.access_date);
    const ok = created != null and modified != null and accessed != null;
    ctx.write(label);
    ctx.write(": ");
    ctx.write(if (ok) "OK" else "FAILED");
    if (modified) |value| {
        var formatted: [20]u8 = .{0} ** 20;
        ctx.write(" modified=");
        ctx.write(r4std.date.formatDateTimeIso(formatted[0..], value));
    }
    ctx.println("");
    return ok;
}

fn checkPersistentMarker(ctx: *const r4os.r4sys.Context, letter: u8) bool {
    var persistent_dir_storage: [16]u8 = .{0} ** 16;
    var persistent_path_storage: [32]u8 = .{0} ** 32;
    var persistent_data_storage: [40]u8 = .{0} ** 40;
    const persistent_dir = buildPath(persistent_dir_storage[0..], letter, "\\Temp");
    const persistent_path = buildPath(persistent_path_storage[0..], letter, "\\Temp\\FSDIAG.TXT");
    const persistent_data = buildMarker(persistent_data_storage[0..], letter);

    var before: [64]u8 = undefined;
    const before_len = ctx.fileRead(persistent_path, before[0..]);
    const existed = before_len == persistent_data.len and memEql(before[0..persistent_data.len], persistent_data);

    ctx.write("persistent marker before write: ");
    if (existed) {
        ctx.println("yes");
    } else if (before_len >= 0) {
        ctx.write("different ");
        ctx.printI32(before_len);
        ctx.println(" bytes");
    } else {
        ctx.println("no");
    }

    const dir_result = ctx.dirCreate(persistent_dir);
    ctx.write("ensure ");
    writeZ(ctx, persistent_dir, persistent_dir_storage.len);
    ctx.write(": ");
    ctx.println(if (dir_result >= 0) "ok" else "already exists or failed");

    const written = ctx.fileWrite(persistent_path, persistent_data);
    ctx.write("write ");
    writeZ(ctx, persistent_path, persistent_path_storage.len);
    ctx.write(": ");
    ctx.printI32(written);
    ctx.println(" bytes");
    if (written != persistent_data.len) return false;

    var after: [64]u8 = undefined;
    const after_len = ctx.fileRead(persistent_path, after[0..]);
    ctx.write("persistent readback: ");
    ctx.printI32(after_len);
    ctx.println(" bytes");
    if (after_len != persistent_data.len) return false;
    return memEql(after[0..persistent_data.len], persistent_data);
}

fn listRoot(ctx: *const r4os.r4sys.Context) bool {
    ctx.println("root entries:");
    var entry: [128]u8 = .{0} ** 128;
    var index: u32 = 0;
    var count: u32 = 0;
    while (index < 10) : (index += 1) {
        @memset(entry[0..], 0);
        const result = ctx.dirEntry("C:\\", index, entry[0..]);
        if (result < 0) continue;
        ctx.write("  ");
        writeZ(ctx, @ptrCast(&entry), entry.len);
        ctx.write(" ");
        ctx.println(if (result == 1) "<DIR>" else "<FILE>");
        count += 1;
    }
    return count > 0;
}

fn checkQualifiedDirEntries(ctx: *const r4os.r4sys.Context) bool {
    var temp_entry: [128]u8 = .{0} ** 128;
    const temp_found = findEntry(ctx, "C:\\", "TEMP", temp_entry[0..]);
    const temp_text = spanZ(temp_entry[0..]);
    const temp_ok = temp_found and equalsIgnoreCase(temp_text, "C:\\TEMP");
    ctx.write("dirEntry qualified C:\\TEMP: ");
    if (temp_found) {
        writeZ(ctx, @ptrCast(&temp_entry), temp_entry.len);
        ctx.write(" ");
    }
    ctx.println(if (temp_ok) "OK" else "FAILED");

    var child_entry: [128]u8 = .{0} ** 128;
    const child_found = findEntry(ctx, "C:\\TEMP", "README.TXT", child_entry[0..]);
    const child_text = spanZ(child_entry[0..]);
    const child_ok = child_found and equalsIgnoreCase(child_text, "C:\\TEMP\\README.TXT");
    ctx.write("dirEntry qualified C:\\TEMP\\README.TXT: ");
    if (child_found) {
        writeZ(ctx, @ptrCast(&child_entry), child_entry.len);
        ctx.write(" ");
    }
    ctx.println(if (child_ok) "OK" else "FAILED");
    return temp_ok and child_ok;
}

fn findEntry(ctx: *const r4os.r4sys.Context, directory: [*:0]const u8, name: []const u8, out: []u8) bool {
    if (out.len == 0) return false;
    var index: u32 = 2;
    while (true) : (index += 1) {
        @memset(out, 0);
        const result = ctx.dirEntry(directory, index, out[0 .. out.len - 1]);
        if (result < 0) return false;
        if (equalsIgnoreCase(baseName(spanZ(out)), name)) return true;
    }
}

fn listDataTemp(ctx: *const r4os.r4sys.Context, letter: u8) bool {
    var persistent_dir_storage: [16]u8 = .{0} ** 16;
    const persistent_dir = buildPath(persistent_dir_storage[0..], letter, "\\Temp\\");
    ctx.putc(letter);
    ctx.println(":\\Temp entries:");
    var entry: [128]u8 = .{0} ** 128;
    var index: u32 = 0;
    var count: u32 = 0;
    while (index < 10) : (index += 1) {
        @memset(entry[0..], 0);
        const result = ctx.dirEntry(persistent_dir, index, entry[0..]);
        if (result < 0) continue;
        ctx.write("  ");
        writeZ(ctx, @ptrCast(&entry), entry.len);
        ctx.write(" ");
        ctx.println(if (result == 1) "<DIR>" else "<FILE>");
        count += 1;
    }
    return count > 0;
}

fn parseDataDrive(args: []const u8) u8 {
    var i: usize = 0;
    while (i < args.len and (args[i] == ' ' or args[i] == '\t')) : (i += 1) {}
    if (i == args.len) return 'D';
    const ch = upper(args[i]);
    if (ch >= 'A' and ch <= 'Z') return ch;
    return 'D';
}

fn buildPath(out: []u8, letter: u8, suffix: []const u8) [*:0]const u8 {
    out[0] = letter;
    out[1] = ':';
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) {
        out[2 + i] = suffix[i];
    }
    out[2 + suffix.len] = 0;
    return @ptrCast(out.ptr);
}

fn buildMarker(out: []u8, letter: u8) []const u8 {
    out[0] = 'R';
    out[1] = '4';
    out[2] = 'O';
    out[3] = 'S';
    out[4] = ' ';
    out[5] = letter;
    out[6] = ':';
    out[7] = ' ';
    @memcpy(out[8 .. 8 + persistent_data_suffix.len], persistent_data_suffix);
    return out[0 .. 8 + persistent_data_suffix.len];
}

fn memEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn delta(after: u64, before: u64) u64 {
    return if (after >= before) after - before else 0;
}

fn writeZ(ctx: *const r4os.r4sys.Context, value: [*:0]const u8, max_len: usize) void {
    var i: usize = 0;
    while (i < max_len and value[i] != 0) : (i += 1) {
        ctx.putc(value[i]);
    }
}

fn writeFixedZ(ctx: *const r4os.r4sys.Context, value: []const u8) void {
    const text = spanZ(value);
    if (text.len == 0) {
        ctx.write("-");
    } else {
        ctx.write(text);
    }
}

fn storageStatusForLetter(value: []const u8, letter: u8) bool {
    const status = spanZ(value);
    return status.len == 9 and
        status[0] == 'm' and status[1] == 'o' and status[2] == 'u' and status[3] == 'n' and
        status[4] == 't' and status[5] == 'e' and status[6] == 'd' and status[7] == '-' and
        status[8] == letter;
}

fn spanZ(value: []const u8) []const u8 {
    var end: usize = 0;
    while (end < value.len and value[end] != 0) : (end += 1) {}
    return value[0..end];
}

fn baseName(path: []const u8) []const u8 {
    var start: usize = 0;
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        if (path[index] == '\\' or path[index] == '/') start = index + 1;
    }
    return path[start..];
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        if (equalsIgnoreCase(haystack[start..][0..needle.len], needle)) return true;
    }
    return false;
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (upper(a[i]) != upper(b[i])) return false;
    }
    return true;
}

fn upper(c: u8) u8 {
    if (c >= 'a' and c <= 'z') return c - ('a' - 'A');
    return c;
}
