# VIP Games Sploits

Five exploit scripts for five flag slots:

1. `exploit_achievements.py` - achievement board detail leak.
2. `exploit_puzzle.py` - solved preview hidden payload leak.
3. `exploit_petfarm.py` - booster confused-deputy leak.
4. `exploit_alchemy.py` - finalize state-machine leak.
5. `exploit_cards.py` - trade duplication leak.

Helper:

- `exploit_all.py` - run all five scripts.

## Usage

```bash
python3 exploit_achievements.py <host>
python3 exploit_puzzle.py <host> --start 1 --end 3000
python3 exploit_petfarm.py <host> --start 1 --end 3000
python3 exploit_alchemy.py <host> --start 1 --end 3000
python3 exploit_cards.py <host> --start 1 --end 3000
python3 exploit_all.py <host>
```

Targeted mode is preferred when the AD platform exposes `flag_id`:

```bash
python3 exploit_achievements.py <host> --flag-id '<flag_id>'
python3 exploit_puzzle.py <host> --flag-id '<flag_id>'
python3 exploit_petfarm.py <host> --flag-id '<flag_id>'
python3 exploit_alchemy.py <host> --flag-id '<flag_id>'
python3 exploit_cards.py <host> --flag-id '<flag_id>'
```

Pet Farm, Alchemy, and Cards use their intended business-logic bugs:

- Pet Farm creates an attacker booster and applies it to the target pet.
- Alchemy calls finalize on the target run and receives the already finalized artifact.
- Cards creates and accepts a trade that duplicates the target card to the attacker.

`<host>` examples:

- `10.10.10.5` uses hardcoded service port `8642`
- `10.10.10.5:8642`
- `http://10.10.10.5:8642`

Optional flag pattern (default: `[A-Z0-9_]{16,}`):

```bash
python3 exploit_puzzle.py <host> --pattern 'FLAG\\{[A-Za-z0-9_\\-]+\\}'
```
