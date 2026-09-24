fn main() {
    // The hardware is 1×, but macOS previews also need 2× glyphs on Retina.
    // Keep these extra bitmap sizes out of the embedded Linux executable.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        let mut sizes = std::env::var("SLINT_FONT_SIZES").unwrap_or_default();
        if !sizes.is_empty() {
            sizes.push(',');
        }
        sizes.push_str("20,22,24,30,32,36,46,58,86,104");
        // Build scripts start single-threaded; set this before Slint starts workers.
        unsafe { std::env::set_var("SLINT_FONT_SIZES", sizes) };
    }
    let config = slint_build::CompilerConfiguration::new()
        .embed_resources(slint_build::EmbedResourcesKind::EmbedForSoftwareRenderer);

    slint_build::compile_with_config("ui/dashboard.slint", config)
        .expect("failed to compile dashboard UI");
}
