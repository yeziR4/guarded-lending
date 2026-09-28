import type { NextConfig } from "next";
import path from "path";

const nextConfig: NextConfig = {
  outputFileTracingRoot: path.join(__dirname, "../.."),
  reactStrictMode: true,
  devIndicators: false,
  typescript: {
    ignoreBuildErrors: process.env.NEXT_PUBLIC_IGNORE_BUILD_ERROR === "true",
  },
  eslint: {
    ignoreDuringBuilds: process.env.NEXT_PUBLIC_IGNORE_BUILD_ERROR === "true",
  },
  webpack: (config, { dev }) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
    // Optional peer dependencies of @coinbase/cdp-sdk (pulled in via wagmi's Base Account connector)
    // that it imports unconditionally. This app never uses x402 payments, so resolve them to empty modules.
    config.resolve.alias = {
      ...config.resolve.alias,
      "@x402/core": false,
      "@x402/evm": false,
      "@x402/extensions": false,
      "@x402/svm": false,
    };
    config.externals.push("pino-pretty", "lokijs", "encoding");
    if (dev) {
      config.watchOptions = {
        followSymlinks: true,
      };
      config.snapshot = { ...(config.snapshot as object), managedPaths: [] };
    }
    return config;
  },
};

module.exports = nextConfig;
