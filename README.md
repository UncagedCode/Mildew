# Mildew

Graham voice production from your phone: [Termux instructions](tools/voice_pipeline/README.md).

```bash
./mildew voice setup
./mildew voice audition welcome_01 --takes 3
./mildew voice lock welcome_01 --take 2
./mildew voice build correct_01 wrong_01
```

Choose the audition take you prefer before locking it. Once the small test sounds right,
`./mildew voice build` generates the full fixed-dialogue library and resumes unchanged work from cache.
