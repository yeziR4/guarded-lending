"use client";

import { useState } from "react";
import { formatUnits, parseUnits } from "viem";

type AmountFormProps = {
  action: string;
  unit: string;
  decimals: number;
  max?: bigint;
  disabled?: boolean;
  onSubmit: (amount: bigint) => Promise<void>;
};

/** Numeric input with a MAX shortcut that submits the amount in the token's smallest unit. */
export const AmountForm = ({ action, unit, decimals, max, disabled, onSubmit }: AmountFormProps) => {
  const [value, setValue] = useState("");
  const [busy, setBusy] = useState(false);

  let amount: bigint | undefined;
  try {
    amount = value ? parseUnits(value, decimals) : undefined;
  } catch {
    amount = undefined;
  }
  const invalid = amount === undefined || amount <= 0n || (max !== undefined && amount > max);

  const submit = async () => {
    if (invalid || amount === undefined) return;
    setBusy(true);
    try {
      await onSubmit(amount);
      setValue("");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="join w-full">
      <label className="input input-sm join-item w-full">
        <input
          type="text"
          inputMode="decimal"
          placeholder="0.0"
          value={value}
          onChange={e => setValue(e.target.value.trim())}
          disabled={disabled || busy}
        />
        {max !== undefined && (
          <button type="button" className="link text-xs" onClick={() => setValue(formatUnits(max, decimals))}>
            max
          </button>
        )}
        <span className="text-xs text-base-content/60">{unit}</span>
      </label>
      <button
        className="btn btn-sm btn-primary join-item min-w-24"
        onClick={submit}
        disabled={disabled || busy || invalid}
      >
        {busy && <span className="loading loading-spinner loading-xs" />}
        {action}
      </button>
    </div>
  );
};
