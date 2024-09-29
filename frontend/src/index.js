import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import MetamaskProvider from "./contexts/MetamaskProvider"
import { AppContextProvider } from "./contexts/AppContext"

const letsgo = ReactDOM.createRoot(document.getElementById('letsgo'))

letsgo.render(
  <React.StrictMode>
    <MetamaskProvider
      sdkOptions={{
        dappMetadata: {
          name: "QU!D",
          //url: window.location.href,
        },
        infuraAPIKey: 'f63b639faa014cdf98530568a75aa254'
      }}>
      <AppContextProvider>
        <App />
      </AppContextProvider>
    </MetamaskProvider>
  </React.StrictMode>
)

