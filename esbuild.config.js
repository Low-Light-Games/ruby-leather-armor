const esbuild = require("esbuild");
const { sassPlugin } = require("esbuild-sass-plugin");

const isProduction = process.env.RAILS_ENV === "production";
const isWatch = process.argv.includes("--watch");

const buildOptions = {
  entryPoints: [
    "app/javascript/application.tsx",
    "app/javascript/frontpage.tsx",
  ],
  bundle: true,
  outdir: "app/assets/builds",
  format: "iife",
  sourcemap: !isProduction,
  minify: isProduction,
  target: "es2017",
  loader: {
    ".js": "jsx",
    ".ts": "ts",
    ".tsx": "tsx",
  },
  define: {
    "process.env.NODE_ENV": isProduction ? '"production"' : '"development"',
  },
  plugins: [sassPlugin()],
};

if (isWatch) {
  esbuild.context(buildOptions).then(ctx => ctx.watch()).catch(() => process.exit(1));
} else {
  esbuild.build(buildOptions).catch(() => process.exit(1));
}
