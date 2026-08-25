class GitTrees < Formula
  desc "Git subcommand for managing a bare-repo plus worktrees layout"
  homepage "https://github.com/brightdigit/git-trees"
  url "https://github.com/brightdigit/git-trees/archive/refs/tags/v1.0.2.tar.gz"
  sha256 "301a8ab3f3a860c8e3125a61d45527f7a2f70a881c41d3d2ea899d47d4b547ef"
  license "MIT"

  def install
    bin.install "git-trees"
    # TREES_AGENTS_TEMPLATE defaults to ~/.config/git-trees/AGENTS.md, which a
    # formula must not write. Stage the template in the prefix and let caveats
    # tell the user how to put it in place.
    pkgshare.install "AGENTS.md.template"
  end

  def caveats
    <<~EOS
      `git trees init` and `git trees root --agents` seed an AGENTS.md at the
      container root from TREES_AGENTS_TEMPLATE, which defaults to
      ~/.config/git-trees/AGENTS.md. Formulae cannot write there, so copy the
      bundled template yourself:

        mkdir -p ~/.config/git-trees
        cp #{pkgshare}/AGENTS.md.template ~/.config/git-trees/AGENTS.md

      Or point TREES_AGENTS_TEMPLATE at the bundled copy instead:

        export TREES_AGENTS_TEMPLATE=#{pkgshare}/AGENTS.md.template
    EOS
  end

  test do
    # `help` writes its usage to stderr and exits 0.
    assert_match "usage: git trees", shell_output("#{bin}/git-trees help 2>&1")
  end
end
