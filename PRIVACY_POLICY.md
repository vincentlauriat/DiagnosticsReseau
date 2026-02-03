# Politique de confidentialité — Mon Réseau

**Dernière mise à jour : 3 février 2025**

## Introduction

Mon Réseau est une application macOS développée par SmartColibri. Cette politique de confidentialité explique comment l'application traite vos données.

## Données collectées

### Données stockées localement

Mon Réseau stocke les données suivantes **uniquement sur votre appareil** (dans le conteneur sandbox de l'application) :

- **Historique des tests de débit** : résultats des tests (vitesse, latence, date, localisation approximative)
- **Historique de qualité réseau** : mesures de latence, jitter et perte de paquets sur 24 heures
- **Profils réseau** : noms de réseaux WiFi et statistiques de performance associées
- **Favoris** : cibles de requêtes DNS, WHOIS et Traceroute sauvegardées
- **Préférences** : réglages de l'application (apparence, notifications, etc.)

### Données transmises à des services externes

L'application communique avec les services suivants pour son fonctionnement :

| Service | Données envoyées | Finalité |
|---------|------------------|----------|
| speed.cloudflare.com | Requêtes HTTP | Mesure de débit (download/upload) |
| one.one.one.one | Requêtes HTTP HEAD | Mesure de latence |
| ipify.org | Requête HTTP | Détection de votre adresse IP publique |
| ipapi.co | Adresse IP | Géolocalisation approximative pour les tests de débit |
| ipwho.is | Adresses IP des routeurs | Géolocalisation des sauts lors du traceroute |
| Serveurs WHOIS (port 43) | Noms de domaine ou adresses IP | Consultation des registres de domaines |
| Serveurs DNS publics | Noms de domaine | Résolution DNS |

**Aucune de ces données n'est collectée, stockée ou traitée par SmartColibri.**

## Localisation

Si vous autorisez l'accès à la localisation, Mon Réseau utilise votre position géographique uniquement pour :
- Afficher votre emplacement lors des tests de débit
- Améliorer la précision des diagnostics réseau

Cette information est stockée localement avec l'historique des tests et n'est jamais transmise à SmartColibri.

## Données non collectées

Mon Réseau **ne collecte pas** :
- Données d'identification personnelle
- Données de navigation
- Informations de contact
- Données financières
- Données de santé
- Données biométriques
- Identifiants publicitaires

## Analyse et publicité

Mon Réseau :
- N'inclut **aucun SDK d'analyse** (pas de Google Analytics, Firebase, etc.)
- N'affiche **aucune publicité**
- Ne partage **aucune donnée** avec des tiers à des fins commerciales

## Sécurité

- Toutes les communications réseau utilisent HTTPS (sauf WHOIS qui utilise le protocole standard sur port 43)
- Les données sont stockées dans le conteneur sandbox de l'application, protégé par macOS
- Aucune donnée n'est transmise à des serveurs SmartColibri

## Vos droits

Vous pouvez à tout moment :
- **Supprimer l'historique** des tests de débit depuis l'application
- **Supprimer l'application** pour effacer toutes les données locales
- **Révoquer l'accès à la localisation** dans Préférences Système > Confidentialité

## Modifications

Cette politique peut être mise à jour occasionnellement. Les modifications seront publiées sur cette page avec une nouvelle date de mise à jour.

## Contact

Pour toute question concernant cette politique de confidentialité :

**SmartColibri**
Email : privacy@smartcolibri.com

---

## Privacy Policy — Mon Réseau (English)

**Last updated: February 3, 2025**

### Summary

Mon Réseau is a network diagnostic application for macOS. It stores all data locally on your device and does not collect, transmit, or share any personal information with SmartColibri or third parties.

The app communicates with external services (Cloudflare, ipify.org, ipapi.co, WHOIS servers, DNS servers) solely to perform network diagnostics. These communications are necessary for the app's functionality and do not involve any data collection by SmartColibri.

**No analytics. No advertising. No tracking.**

For the complete policy, please refer to the French version above or contact us at privacy@smartcolibri.com.
