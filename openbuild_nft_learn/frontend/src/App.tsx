import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from 'react-query';
import { Toaster } from 'react-hot-toast';
import { HelmetProvider } from 'react-helmet-async';

// 页面组件
import HomePage from './pages/HomePage';
import CreatePage from './pages/CreatePage';
import MarketplacePage from './pages/MarketplacePage';
import ProfilePage from './pages/ProfilePage';
import ArtworkDetailPage from './pages/ArtworkDetailPage';
import ExplorePage from './pages/ExplorePage';

// 布局组件
import Layout from './components/Layout';

// 上下文提供者
import { Web3Provider } from './contexts/Web3Context';
import { ThemeProvider } from './contexts/ThemeContext';

// 样式
import './styles/globals.css';

// 创建React Query客户端
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 3,
      retryDelay: 1000,
      refetchOnWindowFocus: false,
      staleTime: 5 * 60 * 1000, // 5分钟
    },
  },
});

function App() {
  return (
    <HelmetProvider>
      <QueryClientProvider client={queryClient}>
        <ThemeProvider>
          <Web3Provider>
            <Router>
              <div className="App min-h-screen bg-gradient-to-br from-purple-50 via-white to-blue-50 dark:from-gray-900 dark:via-gray-800 dark:to-purple-900">
                <Layout>
                  <Routes>
                    {/* 主页 */}
                    <Route path="/" element={<HomePage />} />
                    
                    {/* AI创作页面 */}
                    <Route path="/create" element={<CreatePage />} />
                    
                    {/* NFT市场 */}
                    <Route path="/marketplace" element={<MarketplacePage />} />
                    
                    {/* 探索页面 */}
                    <Route path="/explore" element={<ExplorePage />} />
                    
                    {/* 艺术品详情 */}
                    <Route path="/artwork/:id" element={<ArtworkDetailPage />} />
                    
                    {/* 用户档案 */}
                    <Route path="/profile/:address" element={<ProfilePage />} />
                    <Route path="/profile" element={<ProfilePage />} />
                    
                    {/* 404页面 */}
                    <Route path="*" element={<NotFoundPage />} />
                  </Routes>
                </Layout>
                
                {/* 全局通知 */}
                <Toaster
                  position="top-right"
                  toastOptions={{
                    duration: 4000,
                    style: {
                      background: '#363636',
                      color: '#fff',
                      borderRadius: '12px',
                      padding: '16px',
                      fontSize: '14px',
                    },
                    success: {
                      style: {
                        background: '#10B981',
                      },
                    },
                    error: {
                      style: {
                        background: '#EF4444',
                      },
                    },
                  }}
                />
              </div>
            </Router>
          </Web3Provider>
        </ThemeProvider>
      </QueryClientProvider>
    </HelmetProvider>
  );
}

// 404页面组件
const NotFoundPage: React.FC = () => {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-r from-purple-400 to-blue-500">
      <div className="text-center">
        <h1 className="text-9xl font-bold text-white opacity-50">404</h1>
        <h2 className="text-4xl font-bold text-white mb-4">页面未找到</h2>
        <p className="text-xl text-white mb-8">抱歉，您访问的页面不存在</p>
        <a
          href="/"
          className="inline-flex items-center px-6 py-3 border border-transparent text-base font-medium rounded-md text-purple-700 bg-white hover:bg-gray-50 transition-colors duration-200"
        >
          返回首页
        </a>
      </div>
    </div>
  );
};

export default App; 