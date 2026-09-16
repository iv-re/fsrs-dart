use std::path::Path;

fn main() {
    let include_dir = Path::new("include");
    std::fs::create_dir_all(include_dir).unwrap();
    let header_file = include_dir.join("fsrs_dart.h");
    cbindgen::generate(".")
        .expect("Unable to generate bindings")
        .write_to_file(header_file);
}
