// esbuild の file ローダーで、ファイルの URL(文字列)として取り込まれるもの。
declare module "*.wasm" {
  const url: string;
  export default url;
}

// CSS は副作用のための取り込み(esbuild が main.css にまとめる)。
declare module "*.css";
