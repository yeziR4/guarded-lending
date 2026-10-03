import React from "react";
import { HederaPortalFaucet } from "@scaffold-hbar-ui/components";
import { hedera } from "viem/chains";
import { useTargetNetwork } from "~~/hooks/scaffold-hbar/useTargetNetwork";

/**
 * Site footer
 */
export const Footer = () => {
  const { targetNetwork } = useTargetNetwork();
  const isTestnet = targetNetwork.id !== hedera.id;

  return (
    <div className="min-h-0 py-5 px-1 mb-10">
      <div className="w-full">
        <ul className="menu menu-horizontal w-full">
          <div className="flex justify-center items-center gap-3 text-sm w-full text-base-content/60">
            <a
              href="https://github.com/hedera-dev/scaffold-hbar"
              target="_blank"
              rel="noreferrer"
              className="link hover:text-primary"
            >
              GitHub
            </a>
            <span className="opacity-30">|</span>
            <span>
              Built on{" "}
              <a
                href="https://hedera.com/"
                target="_blank"
                rel="noreferrer"
                className="font-semibold link hover:text-primary"
              >
                Hedera
              </a>
            </span>
            <span className="opacity-30">|</span>
            <a href="https://docs.hedera.com/" target="_blank" rel="noreferrer" className="link hover:text-primary">
              Docs
            </a>
            {isTestnet && (
              <>
                <span className="opacity-30">|</span>
                <HederaPortalFaucet variant="link" label="Testnet HBAR faucet" showIcon={false} />
              </>
            )}
          </div>
        </ul>
      </div>
    </div>
  );
};
