//! `cairo.Surface` — Base class for surfaces
//! `cairo.Surface` is the abstract type representing all different drawing targets
//! that cairo can render to. The actual drawings are performed using a cairo
//! *context*.
//!
//! A cairo surface is created by using *backend*-specific constructors, typically
//! of the form *backend*`Surface.create()`.
//!
//! Most surface types allow accessing the surface without using Cairo functions.
//! If you do this, keep in mind that it is mandatory that you call `surface.flush()`
//! before reading from or writing to the surface and that you must use
//! `surface.markDirty()` after modifying it.
//!
//! **Example 1. Directly modifying an image surface**
//! ```
//! void
//! modify_image_surface (cairo_surface_t *surface)
//! {
//!   unsigned char *data;
//!   int width, height, stride;
//!
//!   // flush to ensure all writing to the image was done
//!   cairo_surface_flush (surface);
//!
//!   // modify the image
//!   data = cairo_image_surface_get_data (surface);
//!   width = cairo_image_surface_get_width (surface);
//!   height = cairo_image_surface_get_height (surface);
//!   stride = cairo_image_surface_get_stride (surface);
//!   modify_image_data (data, width, height, stride);
//!
//!   // mark the image dirty so Cairo clears its caches.
//!   cairo_surface_mark_dirty (surface);
//! }
//! ```
//!
//! Note that for other surface types it might be necessary to acquire the surface's
//! device first. See `cairo.Device.aquire()` for a discussion of devices.
// TODO ^^^ device

const std = @import("std");

const cairo = @import("../cairo.zig");

const util = @import("../util.zig");
const safety = @import("../safety.zig");

const Content = cairo.Content;
const CairoError = cairo.CairoError;
const Device = cairo.Device;
const MimeType = cairo.MimeType;
const Status = cairo.Status;
const SurfaceType = cairo.SurfaceType;
const Format = cairo.Format;
const ImageSurface = @import("image.zig").ImageSurface;
const RectangleInt = util.RectangleInt;

const FontOptions = cairo.FontOptions;
const UserDataKey = cairo.UserDataKey;
const DestroyFn = cairo.DestroyFn;

/// A `cairo.Surface` represents an image, either as the destination of a
/// drawing operation or as source when drawing onto another surface. To draw
/// to a `cairo.Surface`, create a cairo context with the surface as the
/// target, using `cairo.Context.create()`.
///
/// There are different subtypes of `cairo.Surface` for different drawing
/// backends; for example, `cairo.ImageSurface.create()` creates a bitmap image
/// in memory. The type of a surface can be queried with `surface.getType()`.
///
/// The initial contents of a surface after creation depend upon the manner of
/// its creation. If cairo creates the surface and backing storage for the
/// user, it will be initially cleared; for example,
/// `cairo.ImageSurface.create()` and `surface.createSimilar()`. Alternatively,
/// if the user passes in a reference to some backing storage and asks cairo to
/// wrap that in a `cairo.Surface`, then the contents are not modified; for
/// example, `cairo.ImageSurface.createForData()` and
/// `cairo.XlibSurface.create()`.
///
/// Memory management of `cairo.Surface` is done with `surface.reference()`
/// and `surface.destroy()`.
///
/// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-t)
pub const Surface = opaque {
    pub usingnamespace Base(Surface);
};

/// Mixin object, used to inject methods common for all `Surface`s
pub fn Base(comptime Self: type) type {
    return struct {
        /// cast an instance of `cairo.Surface` to a base type; used when the
        /// function can accept any type of surface, example:
        /// ```zig
        /// const ctx = cairo.Context.create(image.asSurface());
        /// ```
        /// where `image` is `cairo.ImageSurface`
        pub inline fn asSurface(surface: *Self) *Surface {
            return @ptrCast(surface);
        }

        /// Create a new surface that is as compatible as possible with an
        /// existing surface. For example the new surface will have the same
        /// device scale, fallback resolution and font options as `surface`.
        /// Generally, the new surface will also use the same backend as
        /// `surface`, unless that is not possible for some reason. The type
        /// of the returned surface may be examined with `surface.getType()`.
        ///
        /// Initially the surface contents are all 0 (transparent if contents
        /// have transparency, black otherwise).
        ///
        /// Use `surface.createSimilarImage()` if you need an image surface
        /// which can be painted quickly to the target surface.
        ///
        /// **Parameters**
        /// - `content`: the content for the new surface
        /// - `width`: width of the new surface, (in device-space units)
        /// - `height`: height of the new surface, (in device-space units)
        ///
        /// **Returns**
        ///
        /// a pointer to the newly allocated surface or fails if `surface` is
        /// already in an error state or any other error occurred.
        ///
        /// **NOTE**: The caller owns the created surface and should call
        /// `surface.destroy()` when done with it. You can use idiomatic Zig
        /// pattern with `defer`:
        /// ```zig
        /// const similar = surface.createSimilar(.Color, 100, 100);
        /// defer similar.destroy();
        /// ```
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-create-similar)
        pub fn createSimilar(surface: *Self, content: Content, width: c_int, height: c_int) CairoError!*Self {
            const s: *Self = @ptrCast(cairo_surface_create_similar(surface, content, width, height).?);
            try s.status().toErr();
            if (safety.tracing) try safety.markForLeakDetection(@returnAddress(), s);
            return s;
        }

        /// Create a new image surface that is as compatible as possible for
        /// uploading to and the use in conjunction with an existing surface.
        /// However, this surface can still be used like any normal image
        /// surface. Unlike `surface.createSimilar()` the new image surface
        /// won't inherit the device scale from `surface`.
        ///
        /// Initially the surface contents are all 0 (transparent if contents
        /// have transparency, black otherwise.)
        ///
        /// Use `surface.createSimilar()` if you don't need an image surface.
        ///
        /// **Parameters**
        /// - `format`: the format for the new surface
        /// - `width`: width of the new surface, (in pixels)
        /// - `height`: height of the new surface, (in pixels)
        ///
        /// **Returns**
        ///
        /// a pointer to the newly allocated image surface or fails if
        /// `surface` is already in an error state or any other error occurs.
        ///
        /// **NOTE**: The caller owns the created surface and should call
        /// `surface.destroy()` when done with it. You can use idiomatic Zig
        /// pattern with `defer`:
        /// ```zig
        /// const image = surface.createSimilarImage(.ARGB32, 100, 100);
        /// defer image.destroy();
        /// ```
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-create-similar-image)
        pub fn createSimilarImage(surface: *Self, format: Format, width: c_int, height: c_int) CairoError!*ImageSurface {
            const image = @as(*ImageSurface, @ptrCast(cairo_surface_create_similar_image(surface, format, width, height).?));
            try image.status().toErr();
            if (safety.tracing) try safety.markForLeakDetection(@returnAddress(), image);
            return image;
        }

        /// Create a new surface that is a rectangle within the target surface.
        /// All operations drawn to this surface are then clipped and
        /// translated onto the target surface. Nothing drawn via this
        /// sub-surface outside of its bounds is drawn onto the target surface,
        /// making this a useful method for passing constrained child surfaces
        /// to library routines that draw directly onto the parent surface,
        /// i.e. with no further backend allocations, double buffering or
        /// copies.
        ///
        /// >The semantics of subsurfaces have not been finalized yet unless
        /// the rectangle is in full device units, is contained within the
        /// extents of the target surface, and the target or subsurface's
        /// device transforms are not changed.
        ///
        /// **Parameters**
        /// - `x`: the x-origin of the sub-surface from the top-left of the
        /// target surface (in device-space units)
        /// - `y`: the y-origin of the sub-surface from the top-left of the
        /// target surface (in device-space units)
        /// - `width`: width of the sub-surface (in device-space units)
        /// - `height`: height of the sub-surface (in device-space units)
        ///
        /// **Returns**
        ///
        /// a pointer to the newly allocated surface or fails if `surface` is
        /// already in an error state or any other error occurs.
        ///
        /// **NOTE**: The caller owns the created surface and should call
        /// `surface.destroy()` when done with it. You can use idiomatic Zig
        /// pattern with `defer`:
        /// ```zig
        /// const image = surface.createSimilarImage(.ARGB32, 100, 100);
        /// defer image.destroy();
        /// ```
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-create-for-rectangle)
        pub fn createForRectangle(surface: *Self, x: f64, y: f64, width: f64, height: f64) CairoError!*Self {
            // TODO: safety
            const s = @as(*Self, @ptrCast(cairo_surface_create_for_rectangle(surface, x, y, width, height).?));
            try s.status().toErr();
            if (safety.tracing) try safety.markForLeakDetection(@returnAddress(), s);
            return s;
        }

        /// Increases the reference count on `surface` by one. This prevents
        /// `surface` from being destroyed until a matching call to
        /// `surface.destroy()` is made.
        ///
        /// Use `surface.getReferenceCount()` to get the number of references
        /// to a `surface`.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-reference)
        pub fn reference(surface: *Self) *Self {
            if (safety.tracing) safety.reference(@returnAddress(), surface);
            return @ptrCast(cairo_surface_reference(surface).?);
        }

        /// Decreases the reference count on `surface` by one. If the result
        /// is zero, then surface and all associated resources are freed. See
        /// `cairo.Surface.reference()`.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-destroy)
        pub fn destroy(surface: *Self) void {
            cairo_surface_destroy(surface);
            if (safety.tracing) safety.destroy(surface);
        }

        /// Checks whether an error has previously occurred for this surface.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-status)
        pub fn status(surface: *Self) Status {
            return cairo_surface_status(surface);
        }

        /// This function finishes the surface and drops all references to
        /// external resources. For example, for the Xlib backend it means that
        /// cairo will no longer access the drawable, which can be freed. After
        /// calling `surface.finish()` the only valid operations on a surface
        /// are getting and setting user, referencing and destroying, and
        /// flushing and finishing it. Further drawing to the surface will not
        /// affect the surface but will instead trigger a
        /// `CairoError.SurfaceFinished` error.
        ///
        /// When the last call to `surface.destroy()` decreases the reference
        /// count to zero, cairo will call `surface.finish()` if it hasn't been
        /// called already, before freeing the resources associated with the
        /// surface.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-finish)
        pub fn finish(surface: *Self) void {
            cairo_surface_finish(surface);
        }

        /// Do any pending drawing for the surface and also restore any
        /// temporary modifications cairo has made to the surface's state.
        /// This function must be called before switching from drawing on the
        /// surface with cairo to drawing on it directly with native APIs, or
        /// accessing its memory outside of Cairo. If the surface doesn't
        /// support direct access, then this function does nothing.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-flush)
        pub fn flush(surface: *Self) void {
            cairo_surface_flush(surface);
        }

        /// This function returns the device for a `surface`. See
        /// `cairo.Device`.
        ///
        /// The device for `surface` or `null` if the surface does not have an
        /// associated device.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-device)
        pub fn getDevice(surface: *Self) ?*Device {
            // TODO: safety checks?
            return cairo_surface_get_device(surface);
        }

        /// Retrieves the default font rendering options for the surface. This
        /// allows display surfaces to report the correct subpixel order for
        /// rendering on them, print surfaces to disable hinting of metrics and
        /// so forth. The result can then be used with
        /// `cairo.ScaledFont.create()`.
        ///
        /// **Parameters**
        /// - `options`: a `cairo.FontOptions` object into which to store the
        /// retrieved options. All existing values are overwritten
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-font-options)
        pub fn getFontOptions(surface: *Self, options: *FontOptions) void {
            cairo_surface_get_font_options(surface, options);
        }

        /// This function returns the content type of `surface` which indicates
        /// whether the surface contains color and/or alpha information.
        /// See `cairo.Content`.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-content)
        pub fn getContent(surface: *Self) Content {
            return cairo_surface_get_content(surface);
        }

        /// Tells cairo that drawing has been done to surface using means other
        /// than cairo, and that cairo should reread any cached areas. Note
        /// that you must call `surface.flush()` before doing such drawing.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-mark-dirty)
        pub fn markDirty(surface: *Self) void {
            cairo_surface_mark_dirty(surface);
        }

        /// Like `surface.markDirty()`, but drawing has been done only to the
        /// specified rectangle, so that cairo can retain cached contents for
        /// other parts of the surface.
        ///
        /// Any cached clip set on the surface will be reset by this function,
        /// to make sure that future cairo calls have the clip set that they
        /// expect.
        ///
        /// **Parameters**
        /// - `rect`: `cairo.RectangleInt` with coordinates and dimensions of
        /// dirty rectangle
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-mark-dirty-rectangle)
        pub fn markDirtyRectangle(surface: *Self, rect: RectangleInt) void {
            cairo_surface_mark_dirty_rectangle(surface, rect.x, rect.y, rect.width, rect.height);
        }

        /// Sets an offset that is added to the device coordinates determined
        /// by the CTM when drawing to `surface`. One use case for this
        /// function is when we want to create a `cairo.Surface` that redirects
        /// drawing for a portion of an onscreen surface to an offscreen
        /// surface in a way that is completely invisible to the user of the
        /// cairo API. Setting a transformation via `cairo.Context.translate()`
        /// isn't sufficient to do this, since functions like
        /// `cairo.Context.deviceToUser()` will expose the hidden offset.
        ///
        /// Note that the offset affects drawing to the surface as well as
        /// using the surface in a source pattern.
        ///
        /// **Parameters**
        /// - `x_offset`: the offset in the X direction, in device units
        /// - `y_offset`: the offset in the Y direction, in device units
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-set-device-offset)
        pub fn setDeviceOffset(surface: *Self, x_offset: f64, y_offset: f64) void {
            cairo_surface_set_device_offset(surface, x_offset, y_offset);
        }

        /// This function returns the previous device offset set by
        /// `cairo.Surface.setDeviceOffset()`.
        ///
        /// **Parameters**
        /// - `x_offset`: the offset in the X direction, in device units
        /// - `y_offset`: the offset in the Y direction, in device units
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-device-offset)
        pub fn getDeviceOffset(surface: *Self, x_offset: *f64, y_offset: *f64) void {
            cairo_surface_get_device_offset(surface, x_offset, y_offset);
        }

        /// Sets a scale that is multiplied to the device coordinates
        /// determined by the CTM when drawing to `surface`. One common use for
        /// this is to render to very high resolution display devices at a
        /// scale factor, so that code that assumes 1 pixel will be a certain
        /// size will still work. Setting a transformation via
        /// `cairo.Context.translate()` isn't sufficient to do this, since
        /// functions like `cairo.Context.deviceToUser()` will expose the
        /// hidden scale.
        ///
        /// Note that the scale affects drawing to the surface as well as using
        /// the surface in a source pattern.
        ///
        /// **Parameters**
        /// - `x_scale`: the scale in the X direction
        /// - `y_scale`: the scale in the Y direction
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-set-device-scale)
        pub fn setDeviceScale(surface: *Self, x_scale: f64, y_scale: f64) void {
            cairo_surface_set_device_scale(surface, x_scale, y_scale);
        }

        /// This function returns the previous device scale set by
        /// `cairo.Surface.setDeviceScale()`.
        ///
        /// **Parameters**
        /// - `x_scale`: the scale in the X direction, in device units
        /// - `y_scale`: the scale in the Y direction, in device units
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-device-scale)
        pub fn getDeviceScale(surface: *Self, x_scale: *f64, y_scale: *f64) void {
            cairo_surface_get_device_scale(surface, x_scale, y_scale);
        }

        /// Set the horizontal and vertical resolution for image fallbacks.
        ///
        /// When certain operations aren't supported natively by a backend,
        /// cairo will fallback by rendering operations to an image and then
        /// overlaying that image onto the output. For backends that are
        /// natively vector-oriented, this function can be used to set the
        /// resolution used for these image fallbacks, (larger values will
        /// result in more detailed images, but also larger file sizes).
        ///
        /// Some examples of natively vector-oriented backends are the ps, pdf,
        /// and svg backends.
        ///
        /// For backends that are natively raster-oriented, image fallbacks are
        /// still possible, but they are always performed at the native device
        /// resolution. So this function has no effect on those backends.
        ///
        /// Note: The fallback resolution only takes effect at the time of
        /// completing a page (with `cairo.Context.showPage()` or
        /// `cairo.Context.copyPage()`) so there is currently no way to have
        /// more than one fallback resolution in effect on a single page.
        ///
        /// The default fallback resoultion is 300 pixels per inch in both
        /// dimensions.
        ///
        /// **Parameters**
        /// - `x_pixels_per_inch`: horizontal setting for pixels per inch
        /// - `y_pixels_per_inch`: vertical setting for pixels per inch
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-set-fallback-resolution)
        pub fn setFallbackResolution(surface: *Self, x_pixels_per_inch: f64, y_pixels_per_inch: f64) void {
            cairo_surface_set_fallback_resolution(surface, x_pixels_per_inch, y_pixels_per_inch);
        }

        /// This function returns the previous fallback resolution set by
        /// `cairo.Surface.setFallbackResolution()`, or default fallback
        /// resolution if never set.
        ///
        /// **Parameters**
        /// - `x_pixels_per_inch`: horizontal pixels per inch
        /// - `y_pixels_per_inch`: vertical pixels per inch
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-fallback-resolution)
        pub fn getFallbackResolution(surface: *Self, x_pixels_per_inch: *f64, y_pixels_per_inch: *f64) void {
            cairo_surface_get_fallback_resolution(surface, x_pixels_per_inch, y_pixels_per_inch);
        }

        /// This function returns the type of the backend used to create a
        /// surface. See `cairo.SurfaceType` for available types.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-type)
        pub fn getType(surface: *Self) SurfaceType {
            return cairo_surface_get_type(surface);
        }

        /// Returns the current reference count of `surface`.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-reference-count)
        pub fn getReferenceCount(surface: *Self) usize {
            return @intCast(cairo_surface_get_reference_count(surface));
        }

        /// Attach user data to `surface`. To remove user data from a surface,
        /// call this function with the key that was used to set it and `null`
        /// for `data`.
        ///
        /// **Parameters**
        /// - `key`: the address of a `cairo.UserDataKey` to attach the user
        /// data to
        /// - `user_data`: the user data to attach to the surface
        /// - `destroyFn`: a `cairo.DestroyFn` which will be called when the
        /// surface is destroyed or when new user data is attached using the
        /// same key.
        ///
        /// The only possible error is `error.OutOfMemory` if a slot could not
        /// be allocated for the user data.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-set-user-data)
        pub fn setUserData(surface: *Self, key: *const UserDataKey, user_data: ?*anyopaque, destroyFn: DestroyFn) CairoError!void {
            return cairo_surface_set_user_data(surface, key, user_data, destroyFn).toErr();
        }

        /// Return user data previously attached to surface using the specified
        /// key. If no user data has been attached with the given key this
        /// function returns `null`.
        ///
        /// **Parameters**
        /// - `key`: the address of a `cairo.UserDataKey` the user data was
        /// attached to
        ///
        /// **Returns**
        ///
        /// the user data previously attached or `null`.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-user-data)
        pub fn getUserData(surface: *Self, key: *const UserDataKey) ?*anyopaque {
            return cairo_surface_get_user_data(surface, key);
        }

        /// Emits the current page for backends that support multiple pages,
        /// but doesn't clear it, so that the contents of the current page
        /// will be retained for the next page. Use `surface.showPage()` if you
        /// want to get an empty page after the emission.
        ///
        /// There is a convenience function for this that works with a
        /// `cairo.Context`, namely `ctx.copyPage()`.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-copy-page)
        pub fn copyPage(surface: *Self) void {
            cairo_surface_copy_page(surface);
        }

        /// Emits and clears the current page for backends that support
        /// multiple pages. Use `surface.copyPage()` if you don't want to clear
        /// the page.
        ///
        /// There is a convenience function for this that works with a
        /// `cairo.Context`, namely `ctx.showPage()`.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-show-page)
        pub fn showPage(surface: *Self) void {
            cairo_surface_show_page(surface);
        }

        /// Returns whether the surface supports sophisticated
        /// `cairo.Context.showTextGlyphs()` operations. That is, whether it
        /// actually uses the provided text and cluster data to a
        /// `ctx.showTextGlyphs()` call.
        ///
        /// Note: Even if this function returns `false`, a
        /// `ctx.showTextGlyphs()` operation targeted at `surface` will still
        /// succeed. It just will act like a `ctx.showGlyphs()` operation.
        /// Users can use this function to avoid computing UTF-8 text and
        /// cluster mapping if the target surface does not use it.
        ///
        /// **Returns**
        ///
        /// `true` if `surface` supports `cairo.Context.showTextGlyphs()`,
        /// `false` otherwise
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-has-show-text-glyphs)
        pub fn hasShowTextGlyphs(surface: *Self) bool {
            return cairo_surface_has_show_text_glyphs(surface) > 0;
        }

        /// Attach an image in the format `mimeType` to `surface`. To remove
        /// the data from a surface, call this function with same mime type and
        /// `null` for `data`.
        ///
        /// The attached image (or filename) data can later be used by backends
        /// which support it (currently: PDF, PS, SVG and Win32 Printing
        /// surfaces) to emit this data instead of making a snapshot of the
        /// `surface`. This approach tends to be faster and requires less
        /// memory and disk space.
        ///
        /// The recognized MIME types are the following: `.Jpeg, `.Png`,
        /// '.Jp2', '.Uri', '.UniqueId', `.Jbig2`, `.Jbig2Global`,
        /// `.Jbig2GlobalId`, `.CcitFax`, `.CcittFaxParams`.
        ///
        /// See corresponding backend surface docs for details about which MIME
        /// types it can handle. Caution: the associated MIME data will be
        /// discarded if you draw on the surface afterwards. Use this function
        /// with care.
        ///
        /// Even if a backend supports a MIME type, that does not mean cairo
        /// will always be able to use the attached MIME data. For example, if
        /// the backend does not natively support the compositing operation
        /// used to apply the MIME data to the backend. In that case, the MIME
        /// data will be ignored. Therefore, to apply an image in all cases, it
        /// is best to create an image surface which contains the decoded image
        /// data and then attach the MIME data to that. This ensures the image
        /// will always be used while still allowing the MIME data to be used
        /// whenever possible.
        ///
        /// **Parameters**
        /// - `mimeType`: the MIME type of the image data
        /// - `data`: the image data to attach to the surface
        /// - `length`: the length of the image data
        /// - `destroy`: a `cairo.DestroyFn` which will be called when the
        /// surface is destroyed or when new image data is attached using the
        /// same mime type.
        /// - `closure`: the data to be passed to the `destroy` notifier
        ///
        /// Fails with `error{ OutOfMemory }` if a slot could not be allocated for the user data.
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-set-mime-data)
        pub fn setMimeData(surface: *Self, mimeType: MimeType, data: [*c]const u8, length: u64, destroyFn: util.DestroyFn, closure: ?*anyopaque) CairoError!void {
            // TODO: data+length, consider slice?
            return cairo_surface_set_mime_data(surface, mimeType.toString().ptr, data, @intCast(length), destroyFn, closure).toErr();
        }

        /// Return mime data previously attached to `surface` using the
        /// specified mime type. If no data has been attached with the given
        /// mime type, `data` is set `null`.
        ///
        /// **Parameters**
        /// - `mimeType`: the MIME type of the image data
        /// - `data`: the image data to attached to the surface
        /// - `length`: the length of the image data
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-get-mime-data)
        pub fn getMimeData(surface: *Self, mimeType: MimeType, data: [*c][*c]const u8, length: *u64) void {
            cairo_surface_get_mime_data(surface, mimeType.toString().ptr, data, @ptrCast(length));
        }

        /// Return whether `surface` supports `mimeType`
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-supports-mime-type)
        pub fn supportsMimeType(surface: *Self, mimeType: MimeType) bool {
            return cairo_surface_supports_mime_type(surface, mimeType.toString().ptr) != 0;
        }

        /// Returns an image surface that is the most efficient mechanism for
        /// modifying the backing store of the target surface. The region
        /// retrieved may be limited to the `extents` or `null` for the whole
        /// surface.
        ///
        /// Note, the use of the original surface as a target or source whilst
        /// it is mapped is undefined. The result of mapping the surface
        /// multiple times is undefined. Calling `surface.destroy()` or
        /// `surface.finish()` on the resulting image surface results in
        /// undefined behavior. Changing the device transform of the image
        /// surface or of `surface` before the image surface is unmapped
        /// results in undefined behavior.
        ///
        /// **Parameters**
        /// - `extents`: limit the extraction to an rectangular region
        ///
        /// **Returns**
        ///
        /// a pointer to the newly allocated image surface or an error if
        /// `surface` in an error state or any other error occurs.
        ///
        /// **NOTE**: the
        /// caller owns the surface, **BUT** calling `.destroy()` on the
        /// resulting `cairo.ImageSurface` is an **UNDEFINED BEHAVIOR**.
        /// Instead, you should call `.unmapImage()` on the original surface as
        /// such:
        /// ```zig
        /// // surface is some cairo.Surface
        /// const extents = cairo.RectangleInt.init(.{0, 0, 10, 10});
        /// const image = try surface.mapToImage(&extents);
        /// defer surface.unmapImage(image);
        /// ```
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-map-to-image)
        pub fn mapToImage(surface: *Self, extents: ?*const RectangleInt) CairoError!*ImageSurface {
            // TODO: this is the only case where the user can screw up garbage
            // collection while using provided .destroy() function. Should we
            // cover this case in debug mode?
            const image = cairo_surface_map_to_image(surface, extents).?;
            try image.status().toErr();
            if (safety.tracing) try safety.markForLeakDetection(@returnAddress(), image);
            return image;
        }

        /// Unmaps the image surface as returned from `surface.mapToImage()`.
        ///
        /// The content of the image will be uploaded to the target surface.
        /// Afterwards, the image is destroyed.
        ///
        /// Using an image surface which wasn't returned by
        /// `surface.mapToImage()` results in undefined behavior.
        ///
        /// **Parameters**
        /// - `image`: the currently mapped image
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-cairo-surface-t.html#cairo-surface-unmap-image)
        pub fn unmapImage(surface: *Self, image: *ImageSurface) void {
            cairo_surface_unmap_image(surface, image);
            if (safety.tracing) safety.destroy(image);
        }

        /// Writes the contents of surface to a new file `filename` as a PNG
        /// image.
        ///
        /// **Parameters**
        /// - `filename`: the name of a file to write to; on Windows this
        /// filename is encoded in UTF-8.
        ///
        /// Possible errors are:
        /// ```zig
        /// error{ OutOfMemory, SurfaceTypeMismatch, WriteError, PngError }
        /// ```
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-PNG-Support.html#cairo-surface-write-to-png)
        pub fn writeToPNG(surface: *Self, filename: []const u8) (CairoError || error{NameTooLong})!void {
            var buf: [4097]u8 = undefined;
            const fileNameZ = std.fmt.bufPrintZ(&buf, "{s}", .{filename}) catch return error.NameTooLong;
            return cairo_surface_write_to_png(surface, fileNameZ.ptr).toErr();
        }

        /// Writes the image surface to the `writer` stream.
        ///
        /// **Parameters**
        /// - `writer`: pointer to a writeable object, e.g. `std.io.Writer` or
        /// `std.fs.File` (it should have a `.writeAll()` function)
        ///
        /// Possible errors are:
        /// ```zig
        /// error{ OutOfMemory, SurfaceTypeMismatch, PngError }
        /// ```
        ///
        /// [Link to Cairo manual](https://www.cairographics.org/manual/cairo-PNG-Support.html#cairo-image-surface-create-from-png-stream)
        pub fn writeToPNGStream(surface: *Self, writer: anytype) CairoError!void {
            const writeFn = util.createWriteFn(@TypeOf(writer));
            return cairo_surface_write_to_png_stream(surface, writeFn, writer).toErr();
        }
    };
}

extern fn cairo_surface_create_similar(other: ?*anyopaque, content: Content, width: c_int, height: c_int) ?*anyopaque;
extern fn cairo_surface_create_similar_image(other: ?*anyopaque, format: Format, width: c_int, height: c_int) ?*anyopaque;
extern fn cairo_surface_create_for_rectangle(target: ?*anyopaque, x: f64, y: f64, width: f64, height: f64) ?*anyopaque;
extern fn cairo_surface_reference(surface: ?*anyopaque) ?*anyopaque;
extern fn cairo_surface_destroy(surface: ?*anyopaque) void;
extern fn cairo_surface_status(surface: ?*anyopaque) Status;
extern fn cairo_surface_finish(surface: ?*anyopaque) void;
extern fn cairo_surface_flush(surface: ?*anyopaque) void;
extern fn cairo_surface_get_device(surface: ?*anyopaque) ?*Device;
extern fn cairo_surface_get_font_options(surface: ?*anyopaque, options: ?*FontOptions) void;
extern fn cairo_surface_get_content(surface: ?*anyopaque) Content;
extern fn cairo_surface_mark_dirty(surface: ?*anyopaque) void;
extern fn cairo_surface_mark_dirty_rectangle(surface: ?*anyopaque, x: c_int, y: c_int, width: c_int, height: c_int) void;
extern fn cairo_surface_set_device_offset(surface: ?*anyopaque, x_offset: f64, y_offset: f64) void;
extern fn cairo_surface_get_device_offset(surface: ?*anyopaque, x_offset: [*c]f64, y_offset: [*c]f64) void;
extern fn cairo_surface_get_device_scale(surface: ?*anyopaque, x_scale: [*c]f64, y_scale: [*c]f64) void;
extern fn cairo_surface_set_device_scale(surface: ?*anyopaque, x_scale: f64, y_scale: f64) void;
extern fn cairo_surface_set_fallback_resolution(surface: ?*anyopaque, x_pixels_per_inch: f64, y_pixels_per_inch: f64) void;
extern fn cairo_surface_get_fallback_resolution(surface: ?*anyopaque, x_pixels_per_inch: [*c]f64, y_pixels_per_inch: [*c]f64) void;
extern fn cairo_surface_get_type(surface: ?*anyopaque) SurfaceType;
extern fn cairo_surface_get_reference_count(surface: ?*anyopaque) c_uint;
extern fn cairo_surface_set_user_data(surface: ?*anyopaque, key: [*c]const UserDataKey, user_data: ?*anyopaque, destroy: DestroyFn) Status;
extern fn cairo_surface_get_user_data(surface: ?*anyopaque, key: [*c]const UserDataKey) ?*anyopaque;
extern fn cairo_surface_copy_page(surface: ?*anyopaque) void;
extern fn cairo_surface_show_page(surface: ?*anyopaque) void;
extern fn cairo_surface_has_show_text_glyphs(surface: ?*anyopaque) c_int;

extern fn cairo_surface_set_mime_data(surface: ?*anyopaque, mime_type: [*c]const u8, data: [*c]const u8, length: c_ulong, destroy: util.DestroyFn, closure: ?*anyopaque) Status;
extern fn cairo_surface_get_mime_data(surface: ?*anyopaque, mime_type: [*c]const u8, data: [*c][*c]const u8, length: [*c]c_ulong) void;
extern fn cairo_surface_supports_mime_type(surface: ?*anyopaque, mime_type: [*c]const u8) c_int;
extern fn cairo_surface_map_to_image(surface: ?*anyopaque, extents: [*c]const RectangleInt) ?*ImageSurface;
extern fn cairo_surface_unmap_image(surface: ?*anyopaque, image: ?*ImageSurface) void;

extern fn cairo_surface_write_to_png(surface: ?*anyopaque, filename: [*c]const u8) Status;
extern fn cairo_surface_write_to_png_stream(surface: ?*anyopaque, write_func: util.WriteFn, closure: ?*anyopaque) Status;
