use std::path::Path;

fn main() {
    println!("cargo:rerun-if-changed=lib.rs");
    println!("cargo:rerun-if-changed=cbindgen.toml");

    let mut generated = Vec::new();
    cbindgen::generate(".")
        .expect("Unable to generate bindings")
        .write(&mut generated);

    let include_dir = Path::new("include");
    let header_file = include_dir.join("fsrs_dart.h");
    if std::fs::read(&header_file).ok().as_deref() == Some(generated.as_slice()) {
        return;
    }

    if std::fs::create_dir_all(include_dir).is_ok() {
        let _ = std::fs::write(header_file, generated);
    }
}
