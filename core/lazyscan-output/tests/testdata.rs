use sha2::{Digest, Sha256};

#[test]
fn testdata_matches_sha256sums() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../testdata/output");
    let sums = std::fs::read_to_string(dir.join("SHA256SUMS")).unwrap();
    let mut listed = Vec::new();
    for line in sums.lines() {
        let (hash, name) = line.split_once(" *").unwrap();
        let actual: String = Sha256::digest(std::fs::read(dir.join(name)).unwrap())
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        assert_eq!(actual, hash, "{name}");
        listed.push(name.to_owned());
    }
    let mut files: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| !n.starts_with('.') && n != "SHA256SUMS")
        .collect();
    files.sort();
    listed.sort();
    assert_eq!(files, listed);
}
