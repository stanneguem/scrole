# Mise en service des liens de partage Scrole (`scrole.fun`)

Le code Flutter reconnaît les liens canoniques :

- `https://scrole.fun/post/<postId>`
- `https://www.scrole.fun/post/<postId>`

Il faut encore configurer l'hébergement du domaine et les fichiers d'association. Les commits du dépôt ne publient pas automatiquement de fichiers sur le domaine.

## 1. DNS et hébergement web

1. Configure le DNS de `scrole.fun` vers un hébergement HTTPS que tu contrôles.
2. Configure aussi `www.scrole.fun` (ou redirige-le vers le domaine principal en conservant la prise en charge du lien).
3. La page `/post/<postId>` doit retourner une page web utile si l'application n'est pas installée. À terme, cette page peut afficher le contenu public accessible et proposer le téléchargement de Scrole.
4. Le certificat TLS doit être valide.

## 2. Android App Links

Le manifeste Android est préparé pour les deux domaines. Pour que le système vérifie les liens, héberge à cette adresse exacte :

`https://scrole.fun/.well-known/assetlinks.json`

Exemple de structure (remplace les valeurs d'exemple par les vraies valeurs de production avant publication) :

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "TON_IDENTIFIANT_APPLICATION_ANDROID",
      "sha256_cert_fingerprints": [
        "EMPREINTE_SHA256_DU_CERTIFICAT_DE_SIGNATURE"
      ]
    }
  }
]
```

Le même fichier doit être accessible sur `https://www.scrole.fun/.well-known/assetlinks.json` si le sous-domaine `www` est utilisé. Le nom du package et l'empreinte SHA-256 doivent correspondre à la version réellement signée (Play App Signing si l'application est publiée sur Google Play).

## 3. iOS Universal Links

Les domaines `scrole.fun` et `www.scrole.fun` sont ajoutés aux Associated Domains de Runner. Il faut héberger un fichier sans extension, sans redirection, à :

- `https://scrole.fun/.well-known/apple-app-site-association`
- `https://www.scrole.fun/.well-known/apple-app-site-association`

Exemple de structure à compléter avec le vrai Team ID Apple et le Bundle ID de production :

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["TEAM_ID_APPLE.BUNDLE_ID_IOS"],
        "components": [
          { "/": "/post/*", "comment": "Ouvrir les liens de publications Scrole" }
        ]
      }
    ]
  }
}
```

Le Bundle ID actuel dans le projet iOS est `com.example.scrole`, qui semble être une valeur de développement. Confirme le Bundle ID définitif et utilise le Team ID du compte Apple qui signe l'application.

## 4. Test de bout en bout

1. Vérifie que les deux fichiers d'association sont servis en HTTPS avec le contenu JSON attendu et sans redirection.
2. Installe une build Android/iOS signée avec les identifiants correspondants.
3. Envoie un lien réel `https://scrole.fun/post/<id>` dans Messages/WhatsApp et clique dessus.
4. Vérifie que la publication s'ouvre dans Scrole, et que les contenus privés/inaccessibles restent protégés par les contrôles backend.
5. Teste aussi le lien sans application installée : le site web doit alors fournir une page de repli.

**Important :** ne publie pas les exemples de ce document tels quels. Il manque encore les identifiants réels de signature et la configuration de l'hébergement.
