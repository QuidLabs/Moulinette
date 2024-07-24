import { useContext, useEffect, useState } from 'react';
import { BrowserRouter as Router, Link } from 'react-router-dom';

import { NotificationList } from './components/NotificationList';
import { Footer } from './components/Footer';
import { Header } from './components/Header';

import { NotificationContext, NotificationProvider } from './contexts/NotificationProvider';
import { useAppContext } from "./contexts/AppContext";

import { useRoutes } from './Routes';

import './App.scss';

function App() {
  const routes = useRoutes();
  const [currentPage, setCurrentPage] = useState('home');
  
  const { quid, account } = useAppContext();

  const [userInfo, setUserInfo] = useState(null);

  const { notify } = useContext(NotificationContext);

  useEffect(() => {
    const fetchData = async () => {
      if (account && quid) {
        await quid.methods.get_info(account)
          .call()
          .then(info => {
            setUserInfo(info);
            console.log("THERE IS INFO: ", info);
          });
      }
    };
    fetchData();
  }, [notify, quid, account]);

  return (
    <NotificationProvider>
      <NotificationList />
      <Router>
        <div className="app-root">
          <Header userInfo={userInfo} />
          <nav>
            <Link to="/" onClick={() => setCurrentPage('home')}>Home</Link>
            <Link to="/Mint" onClick={() => setCurrentPage('mint')}>Mint</Link>
          </nav>
          <main className={`app-main ${currentPage}`}>
            <div className="app-container">
              {routes}
            </div>
          </main>
          <Footer />
        </div>
      </Router>
    </NotificationProvider>
  );
}

export default App;
