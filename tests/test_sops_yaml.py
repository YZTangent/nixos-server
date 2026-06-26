import pathlib
import textwrap
from provision.sops_yaml import add_age_key, find_role_key_group

SAMPLE_YAML = textwrap.dedent("""\
    keys:
      - &compute-a1b2c3d4 age1qzv...

    creation_rules:
      - path_regex: secrets/compute-.*\.yaml$
        key_groups:
          - age:
              - *compute-a1b2c3d4
      - path_regex: secrets/server-.*\.yaml$
        key_groups:
          - age: []
""")

def test_find_role_key_group_returns_index_for_existing_role(tmp_path):
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    idx = find_role_key_group(f, "compute")
    assert idx == 0

def test_find_role_key_group_returns_index_for_server(tmp_path):
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    idx = find_role_key_group(f, "server")
    assert idx == 1

def test_find_role_key_group_raises_for_unknown_role(tmp_path):
    import pytest
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    with pytest.raises(ValueError, match="no creation_rule matched role"):
        find_role_key_group(f, "nonexistent")

def test_add_age_key_appends_to_correct_role_group(tmp_path):
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    add_age_key(f, "server", "server-deadbeef", "age1newkey...")
    content = f.read_text()
    assert "&server-deadbeef" in content
    assert "age1newkey..." in content
    # The new key should be under the server rule, not compute
    assert "*server-deadbeef" in content

def test_add_age_key_is_idempotent_for_duplicate_anchor(tmp_path):
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    add_age_key(f, "compute", "compute-a1b2c3d4", "age1qzv...")
    # Should not duplicate the anchor or key
    content = f.read_text()
    assert content.count("&compute-a1b2c3d4") == 1
    assert content.count("age1qzv...") == 1
