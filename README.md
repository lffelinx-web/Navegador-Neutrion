# Neutrin Browser

Un navegador para iOS, más tranquilo y **centrado en la privacidad**. Bloquea anuncios y rastreadores, y tiene modo oscuro para webs y modo lectura. Está hecho en **SwiftUI** y usa **WebKit** (WKWebView), el motor que Apple exige a todos los navegadores de iOS.

![Ícono](NeutrinBrowser/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

## Privacidad

| Función | Cómo funciona |
|---|---|
| **Shields: bloqueo de anuncios y rastreadores** | Unos 200 servicios conocidos de anuncios (DoubleClick, Taboola, Criteo…) y rastreo (Google Analytics, píxel de Meta, Hotjar…) se bloquean **antes de cargar**, con las reglas nativas de WebKit (`WKContentRuleList`). También oculta los huecos vacíos que dejan los anuncios. |
| **Panel de Shields** | El escudo de la barra de direcciones muestra qué se bloqueó en la página y permite apagar Shields en un sitio concreto (la página se recarga). |
| **Estadísticas** | La página de inicio muestra cuántos anuncios y rastreadores se han bloqueado en total. |
| **Enlaces limpios** | Quita parámetros de rastreo (`utm_*`, `fbclid`, `gclid`, `msclkid`…) de los enlaces que abres, compartes o guardas. |
| **Global Privacy Control** | Indica a las webs que no vendan ni compartan tus datos (`navigator.globalPrivacyControl` y la cabecera `Sec-GPC` en las páginas que abres tú). |
| **HTTPS** | Cambia a HTTPS los sitios que lo admiten y avisa (⚠︎) cuando una conexión no es segura. |
| **Pestañas privadas** | No guardan historial, y sus cookies y datos se borran al cerrarlas. Comparten un almacén en memoria que se descarta al cerrar la última. |
| **Buscadores privados** | DuckDuckGo por defecto. También incluye Brave Search, Startpage, Ecosia, Google y Bing. |
| **Datos locales** | Todo se guarda solo en el dispositivo, cifrado con la protección de archivos de iOS. No hay cuentas ni telemetría. |

## Lectura y apariencia

- **Modo lectura**: en artículos aparece un icono 📄 en la barra. El texto se extrae con [Mozilla Readability](https://github.com/mozilla/readability), el mismo motor que usa Firefox, y se muestra limpio. Puedes cambiar el tamaño de letra, elegir entre serif y sans, y usar tema automático, claro, sepia u oscuro. La vista de lectura funciona **sin JavaScript de la página, sin cookies** y con Shields activado.
- **Modo oscuro para webs**: Apagado, Igual que el sistema o Siempre. Invierte las páginas claras sin estropear fotos ni vídeos, y respeta las webs que ya tienen diseño oscuro.

## Pantallas

| Pantalla | Qué hace |
|---|---|
| **Inicio** | Buscador con escáner QR, accesos rápidos, tarjeta de Shields con estadísticas, Favoritos y Recientes. |
| **Navegador** | Barra flotante: atrás/adelante, escudo con contador, dirección, modo lectura, pestañas y menú (compartir, favoritos, modo oscuro, pestaña privada…). |
| **Tabs & Spaces** | Pestañas por *Spaces* (Personal, Trabajo, Estudio…), una sección **Private** y la gestión de spaces. |
| **Ajustes** | Shields, privacidad, buscador, apariencia, modo lectura y borrado de datos. |

## Requisitos

- Xcode 16 o posterior
- iOS 17 o posterior

## Cómo ejecutarlo

1. Abre `NeutrinBrowser.xcodeproj` en Xcode.
2. Elige tu equipo en *Signing & Capabilities* (o usa el simulador).
3. Pulsa ▶︎ Run.

## Estructura

```
NeutrinBrowser/
├── App/            Punto de entrada y RootView (inicio ↔ navegador)
├── Models/         Space, Tab, Favorite, History, SearchEngine, URLResolver
├── Store/          BrowserStore (estado + persistencia), TabController (WKWebView)
├── Privacy/        Listas de bloqueo, ContentBlocker (WKContentRuleList), LinkCleaner
├── Reader/         Modo lectura: modelos, plantilla HTML y vista
├── Resources/      Scripts JS (Shields, modo oscuro, GPC, Readability)
├── Views/          HomeView, BrowserView, TabsSpacesView, ShieldsPanel, ajustes, escáner QR
├── DesignSystem/   Colores, efecto glass, logo vectorial, ilustraciones
└── Assets.xcassets
```

## Pruebas de los scripts

Los scripts que se inyectan en las páginas (`NeutrinBrowser/Resources/Scripts`) se pueden probar con Node y jsdom: detección de anuncios y rastreadores, modo oscuro, detección de artículos y GPC.

```sh
cd ScriptTests && npm install && npm test
```

## Créditos

- [Mozilla Readability](https://github.com/mozilla/readability) 0.6.0, licencia Apache 2.0 (ver `NeutrinBrowser/Resources/Scripts/Readability-LICENSE.txt`).
