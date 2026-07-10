import argparse
import os
import sqlite3
import numpy as np
import pandas as pd
import lightgbm as lgb

FEATURES = [
    "close0","close1","close5","atr","rsi","ma_slope",
    "vol0","vol1","vol_avg","macd","stoch","sentiment",
    "spread","htf_bias","vol_regime"
]

def load_scaler(path):
    arr = pd.read_csv(path, header=None).values
    if arr.shape[0] != len(FEATURES) or arr.shape[1] < 2:
        raise ValueError(f"Scaler file {path} must have {len(FEATURES)} rows of mean,std")
    means = arr[:, 0].astype(float)
    stds = arr[:, 1].astype(float)
    stds[stds == 0] = 1.0
    return means, stds

def compute_scaler(df):
    means = np.array(df[FEATURES].mean().values, dtype=float, copy=True)
    stds = np.array(df[FEATURES].std(ddof=0).values, dtype=float, copy=True)
    stds[stds == 0] = 1.0
    return means, stds

def save_scaler(path, means, stds):
    with open(path, "w", encoding="utf-8") as f:
        for m, s in zip(means, stds):
            f.write(f"{m},{s}\n")

def load_training_from_db(db_path, table, symbol=None, tf=None, window=0):
    if not os.path.exists(db_path):
        raise SystemExit(f"Database file not found: {db_path}")

    safe_table = table.strip()
    if not safe_table.replace("_", "").isalnum():
        raise SystemExit(f"Unsafe table name: {table}")

    where_clauses = []
    params = []
    if symbol:
        where_clauses.append("symbol = ?")
        params.append(symbol)
    if tf is not None:
        where_clauses.append("tf = ?")
        params.append(int(tf))
    where_sql = f" WHERE {' AND '.join(where_clauses)}" if where_clauses else ""

    cols = ["ts"] + FEATURES + ["label_buy", "label_sell", "label_unified"]
    cols_sql = ",".join(cols)

    conn = sqlite3.connect(db_path)
    try:
        cols_info = pd.read_sql_query(f"PRAGMA table_info({safe_table})", conn)
        if "name" not in cols_info.columns or cols_info.empty:
            raise SystemExit(f"Table not found or unreadable: {safe_table}")

        available_cols = set(cols_info["name"].astype(str).tolist())
        if "ts" in available_cols:
            ts_expr = "ts"
        elif "time" in available_cols:
            ts_expr = "time AS ts"
        else:
            raise SystemExit(f"Missing timestamp column in {safe_table}: expected ts or time")

        if window and window > 0:
            cols_sql_final = f"{ts_expr}," + ",".join(FEATURES + ["label_buy", "label_sell", "label_unified"])
            inner = f"SELECT {cols_sql_final} FROM {safe_table}{where_sql} ORDER BY ts DESC LIMIT ?"
            query = f"SELECT * FROM ({inner}) ORDER BY ts ASC"
            df = pd.read_sql_query(query, conn, params=params + [int(window)])
        else:
            cols_sql_final = f"{ts_expr}," + ",".join(FEATURES + ["label_buy", "label_sell", "label_unified"])
            query = f"SELECT {cols_sql_final} FROM {safe_table}{where_sql} ORDER BY ts ASC"
            df = pd.read_sql_query(query, conn, params=params)
    except Exception as exc:
        raise SystemExit(f"Failed loading training data from DB: {exc}")
    finally:
        conn.close()

    return df

def main():
    ap = argparse.ArgumentParser()
    src_group = ap.add_mutually_exclusive_group(required=True)
    src_group.add_argument("--db", help="SQLite training DB exported by EA")
    src_group.add_argument("--csv", help="Training CSV exported by EA (legacy)")
    ap.add_argument("--table", default="ai_training_data", help="DB table name when using --db")
    ap.add_argument("--symbol", default=None, help="Optional symbol filter when using --db (e.g. XAUUSD)")
    ap.add_argument("--tf", type=int, default=None, help="Optional timeframe filter when using --db (e.g. 15 for M15)")
    ap.add_argument("--label", choices=["buy", "sell", "unified"], default="buy")
    ap.add_argument("--model_out", default="ptb_model.txt")
    ap.add_argument("--scaler_out", default="ptb_scaler.csv")
    ap.add_argument("--init_model", default=None, help="Warm-start/continue training from an existing LightGBM model")
    ap.add_argument("--scaler_in", default=None, help="Scaler to reuse (required when using --init_model)")
    ap.add_argument("--continue_training", action="store_true", help="Continue from --model_out/--scaler_out if they exist")
    ap.add_argument("--window", type=int, default=0, help="Use only the most recent N rows (0=all)")
    ap.add_argument("--min_rows", type=int, default=500, help="Abort if fewer than N rows after filtering")
    ap.add_argument("--num_rounds", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1337)
    args = ap.parse_args()

    if args.db:
        df = load_training_from_db(args.db, args.table, args.symbol, args.tf, args.window)
    else:
        df = pd.read_csv(args.csv)
        if args.window and args.window > 0:
            df = df.tail(args.window).copy()

    if args.label == "unified":
        label_col = "label_unified"
        if label_col not in df.columns:
            df["label_unified"] = 0
            buy = df.get("label_buy", 0)
            sell = df.get("label_sell", 0)
            df.loc[(buy == 1) & (sell == 0), "label_unified"] = 1
            df.loc[(sell == 1) & (buy == 0), "label_unified"] = 2
        df = df[df[label_col].isin([0, 1, 2])].copy()
    else:
        label_col = "label_buy" if args.label == "buy" else "label_sell"
        df = df[df[label_col].isin([0, 1])].copy()

    init_model = args.init_model
    scaler_in = args.scaler_in
    if args.continue_training:
        import os
        if init_model is None and os.path.exists(args.model_out):
            init_model = args.model_out
        if scaler_in is None and os.path.exists(args.scaler_out):
            scaler_in = args.scaler_out

    df = df.dropna(subset=FEATURES + [label_col]).copy()
    df = df[np.isfinite(df[FEATURES]).all(axis=1)].copy()
    if len(df) < args.min_rows:
        raise SystemExit(f"Not enough usable rows after filtering: {len(df)} < {args.min_rows}")

    if init_model:
        if not scaler_in:
            raise SystemExit("--scaler_in (or --continue_training with an existing scaler_out) is required when using --init_model")
        means, stds = load_scaler(scaler_in)
    else:
        means, stds = compute_scaler(df)

    X = (df[FEATURES].values - means) / stds
    y = df[label_col].values

    dtrain = lgb.Dataset(X, label=y)
    if args.label == "unified":
        params = {
            "objective": "multiclass",
            "num_class": 3,
            "metric": "multi_logloss",
            "learning_rate": 0.05,
            "num_leaves": 31,
            "feature_fraction": 0.9,
            "bagging_fraction": 0.9,
            "bagging_freq": 1,
            "verbosity": -1,
            "seed": args.seed
        }
    else:
        params = {
            "objective": "binary",
            "metric": "binary_logloss",
            "learning_rate": 0.05,
            "num_leaves": 31,
            "feature_fraction": 0.9,
            "bagging_fraction": 0.9,
            "bagging_freq": 1,
            "verbosity": -1,
            "seed": args.seed
        }
    booster = lgb.train(params, dtrain, num_boost_round=args.num_rounds, init_model=init_model)

    booster.save_model(args.model_out)
    save_scaler(args.scaler_out, means, stds)

    print(f"Saved model to {args.model_out}")
    print(f"Saved scaler to {args.scaler_out}")
    if init_model:
        print(f"Continued training from {init_model} (+{args.num_rounds} rounds)")

if __name__ == "__main__":
    main()
