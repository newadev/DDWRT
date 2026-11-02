require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'yaml'
require 'json'

class ProjectTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    @tmp = Dir.mktmpdir('ddwrt-test-')
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def run_script(path, *args, dir: @tmp, env: {})
    Open3.capture2e(env, 'bash', path, *args, chdir: dir)
  end

  def test_firmware_checksums_verify_and_source_metadata_survives
    src = File.join(@tmp, 'source')
    target = File.join(src, 'bin/targets/mediatek/filogic')
    write(File.join(target, 'openwrt-test-sysupgrade.itb'), 'firmware')
    write(File.join(target, 'openwrt-test-preloader.bin'), 'bootloader')
    write(File.join(target, 'profiles.json'), '{}')
    write(File.join(target, 'config.buildinfo'), 'config')
    write(File.join(target, 'packages/test.apk'), 'package')
    workflow = YAML.load_file(File.join(ROOT, '.github/workflows/build.yml'))
    step = workflow.fetch('jobs').fetch('build').fetch('steps').find { |s| s['name'] == '整理固件' }
    script = step.fetch('run').gsub('${{ steps.device.outputs.target }}', 'mediatek')
                 .gsub('${{ steps.device.outputs.subtarget }}', 'filogic')
    env_file = File.join(@tmp, 'github-env')
    output, status = Open3.capture2e({ 'SRC' => src, 'GITHUB_WORKSPACE' => ROOT,
      'GITHUB_ENV' => env_file, 'TARGET' => 'mediatek', 'SUBTARGET' => 'filogic',
      'TZ' => 'Asia/Singapore' }, 'bash', '-euo', 'pipefail', '-c', script)
    assert status.success?, output
    firmware_dir = File.readlines(env_file).find { |l| l.start_with?('FIRMWARE=') }.strip.split('=', 2).last
    output, status = Open3.capture2e('sha256sum', '-c', 'sha256sums', chdir: firmware_dir)
    assert status.success?, output
    refute_match(/\s+sha256sums$/, File.read(File.join(firmware_dir, 'sha256sums')))
    assert File.file?(File.join(target, 'profiles.json')), 'Original metadata must survive packaging'
  end

  def test_common_settings_are_idempotent
    generate = File.join(@tmp, 'package/base-files/files/bin/config_generate')
    ttyd = File.join(@tmp, 'feeds/packages/utils/ttyd/files/ttyd.config')
    alpha = File.join(@tmp, 'feeds/nikki/mihomo-alpha/Makefile')
    write(generate, "lan=192.168.1.1\nhostname='OpenWrt'\ntimezone='GMT0'\nzonename='UTC'\n")
    write(ttyd, "option command '/bin/login'\n")
    write(alpha, "  CONFLICTS:=mihomo-meta\n")
    script = File.join(ROOT, 'devices/common/settings.sh')
    output, status = run_script(script)
    assert status.success?, output
    first = [generate, ttyd, alpha].map { |p| File.read(p) }
    output, status = run_script(script)
    assert status.success?, output
    assert_equal first, [generate, ttyd, alpha].map { |p| File.read(p) }
  end

  def test_validator_rejects_all_conflicting_wpad_providers
    config = File.join(@tmp, '.config')
    write(config, "CONFIG_PACKAGE_wpad-basic-mbedtls=y\nCONFIG_PACKAGE_wpad-mbedtls=y\n")
    output, status = run_script(File.join(ROOT, 'tools/validate-config.sh'), config)
    refute status.success?, output
  end

  def test_validator_rejects_wrong_device_profile
    config = File.join(@tmp, '.config')
    write(config, "CONFIG_TARGET_mediatek_filogic_DEVICE_qihoo_360t7=y\n")
    output, status = run_script(File.join(ROOT, 'tools/validate-config.sh'), config,
      'CONFIG_TARGET_mediatek_filogic_DEVICE_qihoo_360t7-ubi')
    refute status.success?, output
  end

  def test_validator_detects_packages_dropped_by_defconfig
    config = File.join(@tmp, '.config')
    requested = File.join(@tmp, 'requested.config')
    write(config, "# CONFIG_PACKAGE_missing is not set\n")
    write(requested, "CONFIG_PACKAGE_missing=y\n")
    output, status = run_script(File.join(ROOT, 'tools/validate-config.sh'), config, '', requested)
    refute status.success?, output
    assert_includes output, 'dropped by defconfig'
  end

  def test_registered_device_profiles_match_the_configs
    workflow = YAML.load_file(File.join(ROOT, '.github/workflows/build.yml'))
    options = workflow.fetch('on').fetch('workflow_dispatch').fetch('inputs').fetch('device').fetch('options')
    mapper = workflow.fetch('jobs').fetch('build').fetch('steps').find { |s| s['id'] == 'device' }.fetch('run')
    options.each do |device|
      match = mapper.match(/\["#{Regexp.escape(device)}"\]="([^"\n]+)"/)
      refute_nil match, "Missing mapping for #{device}"
      target, subtarget, _arch, profile = match[1].split('|')
      config = File.read(File.join(ROOT, 'devices', device, 'target.config'))
      assert_includes config.lines.map(&:chomp), "CONFIG_TARGET_#{target}_#{subtarget}_DEVICE_#{profile}=y"
    end
    configured = Dir[File.join(ROOT, 'devices/*/target.config')].map { |p| File.basename(File.dirname(p)) }
    assert_equal configured.sort, options.sort
  end

  def fixture_project
    project = File.join(@tmp, 'repo')
    FileUtils.mkdir_p(File.join(project, 'tools'))
    FileUtils.cp(File.join(ROOT, 'tools/prepare-source.sh'), File.join(project, 'tools/prepare-source.sh'))
    FileUtils.mkdir_p(File.join(project, 'devices/test'))
    source = File.join(@tmp, 'source')
    write(File.join(source, 'Makefile'), '')
    [project, source]
  end

  def test_feeds_are_appended_consistently_and_duplicate_names_fail
    project, source = fixture_project
    write(File.join(project, 'devices/common/feeds.conf'), "src-git packages https://example.com/packages;main\n")
    extra = File.join(project, 'devices/test/feeds.conf')
    write(extra, "src-git extra https://example.com/extra;main\n")
    script = File.join(project, 'tools/prepare-source.sh')
    2.times do
      output, status = run_script(script, 'test', source, 'feeds')
      assert status.success?, output
    end
    feeds = File.read(File.join(source, 'feeds.conf.default'))
    assert_equal 1, feeds.scan(/^src-git packages /).size
    assert_equal 1, feeds.scan(/^src-git extra /).size
    write(extra, "src-git packages https://example.com/other;main\n")
    output, status = run_script(script, 'test', source, 'feeds')
    refute status.success?, output
    assert_includes output, 'duplicate feed name'
  end

  def test_file_overrides_include_dotfiles
    project, source = fixture_project
    write(File.join(project, 'devices/common/files/etc/.hidden'), 'common')
    write(File.join(project, 'devices/common/files/etc/config/test'), 'common')
    write(File.join(project, 'devices/test/files/etc/config/test'), 'device')
    output, status = run_script(File.join(project, 'tools/prepare-source.sh'), 'test', source, 'files')
    assert status.success?, output
    assert_equal 'common', File.read(File.join(source, 'files/etc/.hidden'))
    assert_equal 'device', File.read(File.join(source, 'files/etc/config/test'))
  end

  def test_patches_are_idempotent_and_invalid_patches_fail
    project, source = fixture_project
    write(File.join(source, 'test.txt'), "before\n")
    patch = File.join(project, 'devices/test/patches/test.patch')
    write(patch, "--- a/test.txt\n+++ b/test.txt\n@@ -1 +1 @@\n-before\n+after\n")
    script = File.join(project, 'tools/prepare-source.sh')
    2.times do
      output, status = run_script(script, 'test', source, 'customize')
      assert status.success?, output
      assert_equal "after\n", File.read(File.join(source, 'test.txt'))
    end
    write(patch, "invalid patch\n")
    output, status = run_script(script, 'test', source, 'customize')
    refute status.success?, output
  end

  def test_config_merge_respects_enabled_and_disabled_device_overrides
    base = File.join(@tmp, 'base.config')
    device = File.join(@tmp, 'device.config')
    write(base, "CONFIG_A=y\n# CONFIG_B is not set\nCONFIG_C=\"common\"\n")
    write(device, "# CONFIG_A is not set\nCONFIG_B=y\nCONFIG_C=\"device\"\n")
    output, status = run_script(File.join(ROOT, 'tools/merge-config.sh'), base, device)
    assert status.success?, output
    assert_equal ["# CONFIG_A is not set", 'CONFIG_B=y', 'CONFIG_C="device"'], output.lines.map(&:chomp)
  end

  def test_packaging_empty_input_fails
    source = File.join(@tmp, 'target')
    write(File.join(source, 'profiles.json'), '{}')
    output, status = run_script(File.join(ROOT, 'tools/prepare-artifacts.sh'), source, File.join(@tmp, 'out'))
    refute status.success?, output
  end

  def test_cudy_expansion_is_scoped_idempotent_and_checks_layout
    dts = File.join(@tmp, 'target/linux/mediatek/dts/mt7981b-cudy-tr3000-v1.dts')
    mk = File.join(@tmp, 'target/linux/mediatek/image/filogic.mk')
    write(dts, "// 0x4000000 elsewhere\n&ubi {\n\treg = <0x5c0000 0x4000000>;\n};\n")
    write(mk, "define Device/cudy_tr3000-v1\n  IMAGE_SIZE := 65536k\nendef\ndefine Device/cudy_tr3000-v1-ubootmod\n  IMAGE_SIZE := 65536k\nendef\n")
    script = File.join(ROOT, 'devices/cudy-tr3000-v1/settings.sh')
    2.times do
      output, status = run_script(script)
      assert status.success?, output
    end
    assert_includes File.read(dts), '// 0x4000000 elsewhere'
    assert_includes File.read(dts), 'reg = <0x5c0000 0x7000000>'
    assert_equal 1, File.read(mk).scan('IMAGE_SIZE := 114688k').size
    write(dts, "&ubi {\n\treg = <0x600000 0x4000000>;\n};\n")
    output, status = run_script(script)
    refute status.success?, output
  end

  def github_script(workflow, step_name, harness)
    steps = YAML.load_file(File.join(ROOT, '.github/workflows', workflow)).fetch('jobs').values.flat_map { |j| j.fetch('steps', []) }
    step = steps.find { |s| s['name'] == step_name }
    script = step.fetch('with').fetch('script')
    node = <<~'JS'
      const fs = require('fs');
      const { script, harness } = JSON.parse(fs.readFileSync(0, 'utf8'));
      const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
      new AsyncFunction('require', 'script', harness)(require, script)
        .catch(error => { console.error(error); process.exitCode = 1; });
    JS
    output, status = Open3.capture2e('node', '-e', node,
      stdin_data: JSON.generate(script: script, harness: harness), chdir: ROOT)
    assert status.success?, output
  end

  def test_update_dispatch_pins_source_and_propagates_failures
    github_script('update-checker.yml', '触发全部设备编译', <<~'JS')
      const assert = require('node:assert/strict');
      const calls = [];
      const github = { rest: { actions: { createWorkflowDispatch: async args => {
        calls.push(args);
        if (calls.length === 2) throw new Error('dispatch unavailable');
      } } } };
      const context = { repo: { owner: 'test', repo: 'test' }, ref: 'refs/heads/main' };
      const core = { summary: { addHeading() {return this}, addRaw() {return this}, async write() {} } };
      process.env.NEW_HASH = 'a'.repeat(40);
      const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
      await assert.rejects(new AsyncFunction('github', 'context', 'core', 'require', script)(github, context, core, require), /dispatch unavailable/);
      assert.equal(calls.length, 2);
      assert.equal(calls[0].inputs.source_ref, process.env.NEW_HASH);
      assert.equal(calls[0].ref, 'main');
    JS
    steps = YAML.load_file(File.join(ROOT, '.github/workflows/update-checker.yml')).fetch('jobs').fetch('check').fetch('steps')
    assert_operator steps.index { |s| s['name'] == '触发全部设备编译' }, :<,
      steps.index { |s| s['name'] == '记录已触发的源码版本' }
    refute steps.any? { |s| s['continue-on-error'] }
  end

  def test_update_watermark_is_a_plain_full_sha_with_a_newline
    steps = YAML.load_file(File.join(ROOT, '.github/workflows/update-checker.yml')).fetch('jobs').fetch('check').fetch('steps')
    script = steps.find { |s| s['name'] == '记录已触发的源码版本' }.fetch('run')
    stub = "git() { if [[ \"$1\" == diff ]]; then return 1; fi; return 0; }\n"
    sha = 'a' * 40
    output, status = Open3.capture2e({ 'NEW_HASH' => sha, 'GITHUB_REF_NAME' => 'main' },
      'bash', '-euo', 'pipefail', '-c', stub + script, chdir: @tmp)
    assert status.success?, output
    assert_equal sha + "\n", File.read(File.join(@tmp, '.last_source_hash'))
  end

  def test_invalid_cleanup_threshold_does_not_delete_caches
    github_script('cache-cleanup.yml', '清理过期缓存', <<~'JS')
      const assert = require('node:assert/strict');
      const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
      for (const value of ['-1', '0', '7days', '1.5', 'Infinity']) {
        let failed = false;
        const core = { setFailed() { failed = true } };
        const github = { rest: { actions: new Proxy({}, { get() { throw new Error('Unexpected API call') } }) } };
        process.env.OLDER_THAN_DAYS = value;
        await new AsyncFunction('github', 'core', script)(github, core);
        assert.equal(failed, true, value);
      }
    JS
  end

  def test_failed_release_deletion_preserves_tag_and_ignores_unmanaged_releases
    github_script('clean-releases-and-runs.yml', 'Delete Older Releases and Tags', <<~'JS')
      const assert = require('node:assert/strict');
      const releases = [];
      for (const device of ['360-t7', 'unmanaged']) {
        for (let i = 1; i <= 3; i++) releases.push({ id: device + i, tag_name: device + '-' + i, created_at: '2026-01-0' + i });
      }
      releases.push({ id: 'draft', tag_name: '360-t7-4', created_at: '2026-01-04', draft: true });
      const deleted = [], tags = [];
      const github = {
        paginate: async () => releases,
        rest: {
          repos: { listReleases() {}, deleteRelease: async args => { deleted.push(args.release_id); throw new Error('denied') } },
          git: { deleteRef: async args => tags.push(args.ref) }
        }
      };
      const context = { repo: { owner: 'test', repo: 'test' } };
      const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
      await new AsyncFunction('github', 'context', 'require', script)(github, context, require);
      assert.deepEqual(deleted, ['360-t71']);
      assert.deepEqual(tags, []);
    JS
  end
end
