<!-- 自動生成: core/scripts/gen-languages.ts。直接編集しない(core/src/grammars.ts を変えたら、`npm run languages` で再生成する) -->

# シンタックスハイライト

コードブロックの言語の指定(` ```elisp `)で、GitHub と同じ文法(starry-night)で着色します。88 言語に対応しています。
指定には、下の「指定できる名前」のどれか(大文字小文字は区別しない)か、拡張子(` ```.el `)を使えます。
言語の指定がない、または一覧にない場合は、着色しません(文書は、そのまま表示されます)。
`mermaid` は着色ではなく、図として描画します。

「文法の読込」は、文法をいつ読み込むかを表します。「必要時に読込」の言語は、文法が大きいため、その言語のコードブロックがある文書を開いたときだけ読み込みます(初めて開くときに、わずかに時間がかかることがあります)。

| 指定できる名前 | 拡張子 | 文法の読込 |
| --- | --- | --- |
| `abuild`, `alpine-abuild`, `apkbuild`, `bash`, `envrc`, `gentoo-ebuild`, `gentoo-eclass`, `openrc`, `openrc-runscript`, `sh`, `shell`, `shell-script`, `tcsh`, `zsh` | `.bash` `.bats` `.command` `.csh` `.ebuild` `.eclass` `.ksh` `.pacscript` `.sbatch` `.sh` `.sh.in` `.slurm` `.tcsh` `.tmux` `.tool` `.zsh` `.zsh-theme` | 常時 |
| `ags`, `ags-script`, `asymptote`, `c++`, `cpp`, `edje-data-collection`, `game-maker-language`, `hip`, `metal`, `sip`, `swig` | `.asc` `.ash` `.asy` `.c++` `.cc` `.cp` `.cpp` `.cppm` `.cxx` `.edc` `.gml` `.h++` `.hh` `.hip` `.hpp` `.hxx` `.inl` `.ino` `.ipp` `.ixx` `.metal` `.re` `.swg` `.swig` `.tcc` `.tpp` `.txx` | 常時 |
| `altium`, `altium-designer`, `conf`, `dosini`, `ini` | `.cnf` `.container` `.dof` `.frm` `.ini` `.lektorproject` `.mount` `.network` `.outjob` `.pcbdoc` `.prefs` `.prjpcb` `.properties` `.schdoc` `.service` `.socket` `.target` `.timer` `.url` | 常時 |
| `apacheconf`, `aconf`, `apache` | `.apacheconf` `.vhost` | 常時 |
| `asciidoc` | `.asciidoc` `.adoc` | 常時 |
| `assembly`, `asm`, `nasm` | `.asm` `.a51` `.i` `.nas` `.nasm` `.s` | 常時 |
| `astro` | `.astro` | 常時 |
| `awk` | `.awk` `.auk` `.gawk` `.mawk` `.nawk` | 常時 |
| `b`, `c`, `dtrace`, `dtrace-script`, `oncrpc`, `opencl`, `pro*c`, `rpc`, `rpcgen`, `unified-parallel-c`, `x-bitmap`, `x-pixmap`, `xbm`, `xdr`, `xpm`, `xs` | `.b` `.c` `.cats` `.h` `.h.in` `.idc` `.opencl` `.pc` `.upc` `.xbm` `.xpm` `.xs` | 常時 |
| `bazel`, `bzl`, `easybuild`, `py`, `py3`, `python`, `python3`, `rusthon`, `sage`, `snakefile`, `snakemake`, `starlark`, `xonsh` | `.bzl` `.eb` `.gyp` `.gypi` `.lmi` `.py` `.py3` `.pyde` `.pyi` `.pyp` `.pyt` `.pyw` `.rpy` `.sage` `.sagews` `.smk` `.snakefile` `.spec` `.tac` `.wsgi` `.xpy` `.xsh` | 常時 |
| `beef`, `c#`, `cake`, `cakescript`, `csharp`, `eq`, `uno` | `.bf` `.cake` `.cs` `.cs.pp` `.csx` `.eq` `.linq` `.uno` | 常時 |
| `bibtex` | `.bib` `.bibtex` | 常時 |
| `buildstream`, `jar-manifest`, `kaitai-struct`, `ksy`, `lookml`, `oasv2-yaml`, `oasv3-yaml`, `raml`, `unity3d-asset`, `yaml`, `yml` | `.anim` `.asset` `.ksy` `.lkml` `.lookml` `.mat` `.meta` `.mir` `.prefab` `.raml` `.reek` `.rviz` `.sublime-syntax` `.syntax` `.unity` `.yaml-tmlanguage` `.yaml.sed` `.yml.mysql` | 常時 |
| `c2hs`, `c2hs-haskell`, `dhall`, `frege`, `haskell` | `.chs` `.dhall` `.hs` `.hs-boot` `.hsc` | 常時 |
| `chuck`, `java`, `unrealscript` | `.ck` `.jav` `.java` `.jsh` `.uc` | 常時 |
| `clojure`, `edn`, `rouge`, `wisp` | `.boot` `.cl2` `.clj` `.cljc` `.cljs` `.cljs.hl` `.cljscm` `.cljx` `.edn` `.hic` `.rg` `.wisp` | 常時 |
| `cmake` | `.cmake` `.cmake.in` | 常時 |
| `collada`, `eagle`, `labview`, `rss`, `web-ontology-language`, `wsdl`, `xml`, `xpages`, `xproc`, `xsd` | `.adml` `.admx` `.ant` `.axaml` `.axml` `.brd` `.builds` `.ccproj` `.ccxml` `.clixml` `.cproject` `.cscfg` `.csdef` `.csproj` `.ct` `.dae` `.depproj` `.dita` `.ditamap` `.ditaval` `.dll.config` `.dotsettings` `.filters` `.fsproj` `.fxml` `.glade` `.gmx` `.gpx` `.grxml` `.hzp` `.icls` `.iml` `.ivy` `.jelly` `.jsproj` `.kml` `.launch` `.lvclass` `.lvlib` `.lvproj` `.mdpolicy` `.meta4` `.mjml` `.mxml` `.natvis` `.ndproj` `.nproj` `.nuspec` `.odd` `.osm` `.owl` `.pkgproj` `.proj` `.props` `.ps1xml` `.psc1` `.pt` `.pubxml` `.qhelp` `.rbxmx` `.rdf` `.resx` `.rss` `.sch` `.sch` `.scxml` `.sfproj` `.shproj` `.slnx` `.srdf` `.storyboard` `.sublime-snippet` `.targets` `.tml` `.ui` `.urdf` `.ux` `.vbproj` `.vcxproj` `.vsixmanifest` `.vssettings` `.vstemplate` `.vxml` `.wixproj` `.wsdl` `.wsf` `.wxi` `.wxl` `.wxs` `.x3d` `.xacro` `.xaml` `.xib` `.xlf` `.xliff` `.xmi` `.xml` `.xml.dist` `.xmp` `.xpl` `.xproc` `.xproj` `.xsd` `.xsp-config` `.xsp.metadata` `.xspec` `.xul` `.zcml` | 常時 |
| `common-lisp`, `lisp` | `.lisp` `.asd` `.cl` `.l` `.lsp` `.ny` `.podsl` `.sexp` | 常時 |
| `crystal` | `.cr` | 常時 |
| `css` | `.css` | 常時 |
| `csv` | `.csv` | 常時 |
| `cycript`, `javascript`, `javascript+erb`, `js`, `json5`, `jsonld`, `node`, `qt-script` | `._js` `.bones` `.cjs` `.cy` `.es6` `.jake` `.javascript` `.js` `.js.erb` `.jsb` `.jscad` `.jsfl` `.jslib` `.jsm` `.json5` `.jsonld` `.jspre` `.jss` `.jsx` `.mjs` `.njs` `.pac` `.sjs` `.ssjs` `.xsjs` `.xsjslib` | 常時 |
| `dart` | `.dart` | 常時 |
| `diff`, `udiff` | `.diff` `.patch` | 常時 |
| `dockerfile`, `containerfile` | `.dockerfile` `.containerfile` | 常時 |
| `ecere-projects`, `geojson`, `ipython-notebook`, `json`, `jsonl`, `jupyter-notebook`, `max`, `max/msp`, `maxmsp`, `oasv2-json`, `oasv3-json`, `sarif`, `topojson` | `.4dform` `.4dproject` `.avsc` `.epj` `.geojson` `.gltf` `.har` `.ice` `.ipynb` `.json` `.json` `.json` `.json-tmlanguage` `.json.example` `.jsonl` `.maxhelp` `.maxpat` `.maxproj` `.mcmeta` `.mxt` `.pat` `.sarif` `.slnlaunch` `.tfstate` `.tfstate.backup` `.topojson` `.webapp` `.webmanifest` `.yy` `.yyp` | 常時 |
| `elixir` | `.ex` `.exs` | 常時 |
| `elm` | `.elm` | 常時 |
| `emacs-lisp`, `cask`, `eask`, `elisp`, `emacs` | `.el` `.emacs` `.emacs.desktop` | 必要時に読込 |
| `erlang` | `.erl` `.app` `.app.src` `.es` `.escript` `.hrl` `.xrl` `.yrl` | 常時 |
| `f#`, `fsharp` | `.fs` `.fsi` `.fsx` | 常時 |
| `fb`, `freebasic`, `realbasic`, `vb-.net`, `vb.net`, `vbnet`, `vbscript`, `visual-basic`, `visual-basic-.net` | `.bi` `.rbbas` `.rbfrm` `.rbmnu` `.rbres` `.rbtbar` `.rbuistate` `.vb` `.vbhtml` `.vbs` | 常時 |
| `fortran` | `.f77` | 常時 |
| `glyph`, `quartus-simulation-ip`, `sdc`, `tcl`, `xdc` | `.adp` `.glf` `.sdc` `.tcl` `.tcl.in` `.tm` `.xdc` | 常時 |
| `go`, `golang` | `.go` | 常時 |
| `gradle-kotlin-dsl`, `kotlin` | `.gradle.kts` `.kt` `.ktm` `.kts` | 常時 |
| `graphql` | `.graphql` `.gql` `.graphqls` | 常時 |
| `graphviz-(dot)` | `.dot` `.gv` | 常時 |
| `groovy` | `.groovy` `.grt` `.gtpl` `.gvy` | 常時 |
| `handlebars`, `hbs`, `htmlbars` | `.handlebars` `.hbs` | 常時 |
| `hcl`, `hashicorp-configuration-language`, `opentofu`, `terraform` | `.hcl` `.nomad` `.tf` `.tfvars` `.tofu` `.workflow` | 常時 |
| `html`, `kit`, `mtml`, `xhtml` | `.hta` `.htm` `.html.hl` `.kit` `.mtml` `.xht` `.xhtml` | 常時 |
| `html+php`, `inc`, `php` | `.aw` `.ctp` `.php3` `.php4` `.php5` `.phps` `.phpt` `.phtml` | 常時 |
| `ignore-list`, `ignore`, `gitignore`, `git-ignore` | `.gitignore` | 常時 |
| `jruby`, `macruby`, `mirah`, `rake`, `rb`, `rbx`, `ruby` | `.builder` `.druby` `.duby` `.eye` `.gemspec` `.god` `.jbuilder` `.mirah` `.mspec` `.pluginspec` `.podspec` `.prawn` `.rabl` `.rake` `.rb` `.rbi` `.rbuild` `.rbw` `.rbx` `.ru` `.ruby` `.thor` `.watchr` | 常時 |
| `json-with-comments`, `jsonc` | `.jsonc` `.code-snippets` `.code-workspace` `.hujson` `.sublime-build` `.sublime-color-scheme` `.sublime-commands` `.sublime-completions` `.sublime-keymap` `.sublime-macro` `.sublime-menu` `.sublime-mousemap` `.sublime-project` `.sublime-settings` `.sublime-theme` `.sublime-workspace` `.sublime_metrics` `.sublime_session` `.tsconfig.json` | 常時 |
| `julia` | `.jl` | 常時 |
| `just`, `justfile` | `.just` | 常時 |
| `less`, `less-css` | `.less` | 常時 |
| `llvm` | `.ll` | 常時 |
| `lua` | `.lua` `.fcgi` `.nse` `.p8` `.pd_lua` `.rbxs` `.rockspec` `.wlua` | 常時 |
| `makefile`, `bsdmake`, `make`, `mf` | `.mak` `.make` `.makefile` `.mk` `.mkfile` | 常時 |
| `markdown`, `md`, `pandoc`, `rmarkdown` | `.livemd` `.markdown` `.mdown` `.mdwn` `.mkd` `.mkdn` `.mkdown` `.qmd` `.rmd` `.ronn` `.scd` `.workbook` | 常時 |
| `matlab`, `octave` | `.matlab` `.m` | 常時 |
| `nginx`, `nginx-configuration-file` | `.nginx` `.nginxconf` | 常時 |
| `nim` | `.nim` `.nim.cfg` `.nimble` `.nimrod` `.nims` | 常時 |
| `nix`, `nixos` | `.nix` | 常時 |
| `objective-c`, `obj-c`, `objc`, `objectivec` |  | 常時 |
| `ocaml` | `.ml` `.eliom` `.eliomi` `.ml4` `.mli` `.mll` `.mly` | 常時 |
| `open-policy-agent` | `.rego` | 常時 |
| `perl`, `cperl` | `.pl` `.cgi` `.perl` `.ph` `.plx` `.pm` `.psgi` `.t` | 常時 |
| `plantuml` | `.puml` `.iuml` `.plantuml` | 常時 |
| `plpgsql`, `sql`, `sqlpl` | `.db2` `.ddl` `.mysql` `.pgsql` `.prc` `.sql` `.sql` `.sql` `.tab` `.udf` `.viw` | 常時 |
| `powershell`, `posh`, `pwsh` | `.ps1` `.psd1` `.psm1` | 常時 |
| `protocol-buffer`, `proto`, `protobuf`, `protocol-buffers` | `.proto` | 常時 |
| `pug` | `.jade` `.pug` | 常時 |
| `purescript` | `.purs` | 常時 |
| `r`, `rscript`, `splus` | `.r` `.rd` `.rhistory` `.rsx` | 常時 |
| `racket` | `.rkt` `.rktd` `.rktl` `.scrbl` | 常時 |
| `regular-expression`, `regexp`, `regex` | `.regexp` `.regex` | 常時 |
| `restructuredtext`, `rst` | `.rst` `.rest` `.rest.txt` `.rst.txt` | 常時 |
| `rust`, `rs` | `.rs` `.rs.in` | 常時 |
| `sass` | `.sass` | 常時 |
| `scala` | `.scala` `.kojo` `.sbt` `.sc` | 常時 |
| `scheme` | `.scm` `.sld` `.sps` `.ss` | 常時 |
| `scss` | `.scss` | 常時 |
| `stylus` | `.styl` | 常時 |
| `svelte` | `.svelte` | 常時 |
| `svg` | `.svg` | 常時 |
| `swift` | `.swift` | 常時 |
| `tex`, `latex` | `.tex` `.aux` `.bbx` `.cbx` `.dtx` `.ins` `.lbx` `.ltx` `.mkii` `.mkiv` `.mkvi` `.sty` `.toc` | 常時 |
| `toml` | `.toml` `.toml.example` | 常時 |
| `tsx`, `typescriptreact` | `.tsx` | 必要時に読込 |
| `typescript`, `ts` | `.ts` `.cts` `.mts` | 常時 |
| `vim-script`, `vim`, `viml`, `nvim`, `vimscript` | `.vim` `.vimrc` `.vmb` | 常時 |
| `vue` | `.vue` | 常時 |
| `zig` | `.zig` `.zig.zon` | 常時 |
