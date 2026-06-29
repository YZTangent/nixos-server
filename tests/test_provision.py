import hashlib
import pathlib
from provision.provision import derive_hash, write_device_id_file

SAMPLE_DMI_UUID = "12345678-1234-4623-8234-123456789012"

def test_derive_hash_returns_8_hex_chars():
    h = derive_hash(SAMPLE_DMI_UUID)
    assert len(h) == 8
    assert all(c in "0123456789abcdef" for c in h)

def test_derive_hash_is_deterministic():
    assert derive_hash(SAMPLE_DMI_UUID) == derive_hash(SAMPLE_DMI_UUID)

def test_derive_hash_matches_expected_value():
    expected = hashlib.sha256(SAMPLE_DMI_UUID.encode()).hexdigest()[:8]
    assert derive_hash(SAMPLE_DMI_UUID) == expected

def test_write_device_id_file_creates_valid_nix(tmp_path):
    out_dir = tmp_path / "device-deadbeef"
    write_device_id_file(out_dir, "deadbeef")
    content = (out_dir / "default.nix").read_text()
    assert 'hostname = "deadbeef"' in content
    assert 'hostId = "deadbeef"' in content

def test_write_device_id_file_overwrites_existing(tmp_path):
    out_dir = tmp_path / "device-deadbeef"
    out_dir.mkdir()
    (out_dir / "default.nix").write_text("# old content")
    write_device_id_file(out_dir, "deadbeef")
    content = (out_dir / "default.nix").read_text()
    assert "old content" not in content
    assert 'hostname = "deadbeef"' in content
