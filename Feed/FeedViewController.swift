import UIKit

import ParseSwift

class FeedViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    private let refreshControl = UIRefreshControl()

    private var posts = [Post]() {
        didSet {
            tableView.reloadData()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        debugPrintLatestPostUserShape()
    }
    
    private func debugPrintLatestPostUserShape() {
        let q = Post.query()
            .order([.descending("createdAt")])
            .limit(1)

        q.find { result in
            switch result {
            case .success(let posts):
                guard let p = posts.first else {
                    print("No posts exist at all")
                    return
                }

                print("LATEST POST DEBUG:")
                print("objectId:", p.objectId ?? "nil")
                print("user:", String(describing: p.user))

            case .failure(let e):
                print("debug query failed:", e.localizedDescription)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsSelection = false

        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(onPullToRefresh), for: .valueChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enforcePostFirstThenLoadFeed()
    }

    private func enforcePostFirstThenLoadFeed() {
        guard let userId = User.current?.objectId else { return }

        var stubUser = User()
        stubUser.objectId = userId

        do {
            let gateQuery = try Post.query()
                .where("user" == stubUser)
                .limit(1)

            gateQuery.find { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let posts):
                        if posts.isEmpty {
                            self?.posts = []
                            print("🚫 Feed locked until first post")
                            return
                        }
                        self?.queryPosts()

                    case .failure(let error):
                        self?.showAlert(description: error.localizedDescription)
                    }
                }
            }

        } catch {
            showAlert(description: error.localizedDescription)
        }
    }
    
    private func queryPosts(completion: (() -> Void)? = nil) {
        
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        
        let query = Post.query()
            .include("user")
            .where("createdAt" >= startOfYesterday)
            .order([.descending("createdAt")])
            .limit(20)
        
        // Find and return posts that meet query criteria (async)
        query.find { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let posts):
                    self?.posts = posts
                case .failure(let error):
                    self?.showAlert(description: error.localizedDescription)
                }
                completion?()
            }
        }
    }

    @IBAction func onLogOutTapped(_ sender: Any) {
        showConfirmLogoutAlert()
    }

    @objc private func onPullToRefresh() {
        refreshControl.beginRefreshing()

        guard let userId = User.current?.objectId else {
            refreshControl.endRefreshing()
            return
        }

        var stubUser = User()
        stubUser.objectId = userId

        do {
            let gateQuery = try Post.query()
                .where("user" == stubUser)
                .limit(1)

            gateQuery.find { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }

                    switch result {
                    case .success(let posts):
                        if posts.isEmpty {
                            self.posts = []
                            self.refreshControl.endRefreshing()
                            return
                        }

                        self.queryPosts {
                            self.refreshControl.endRefreshing()
                        }

                    case .failure:
                        self.refreshControl.endRefreshing()
                    }
                }
            }

        } catch {
            refreshControl.endRefreshing()
            showAlert(description: error.localizedDescription)
        }
    }
    
    private func showConfirmLogoutAlert() {
        let alertController = UIAlertController(title: "Log out of \(User.current?.username ?? "current account")?", message: nil, preferredStyle: .alert)
        let logOutAction = UIAlertAction(title: "Log out", style: .destructive) { _ in
            NotificationCenter.default.post(name: Notification.Name("logout"), object: nil)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alertController.addAction(logOutAction)
        alertController.addAction(cancelAction)
        present(alertController, animated: true)
    }
}

extension FeedViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        posts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "PostCell", for: indexPath) as? PostCell else {
               return UITableViewCell()
           }

           let post = posts[indexPath.row]
           cell.configure(with: post)

           cell.onCommentTapped = { [weak self] in
               guard let self else { return }

               guard let vc = self.storyboard?.instantiateViewController(withIdentifier: "CommentsViewController") as? CommentsViewController else {
                   assertionFailure("CommentsViewController storyboard ID/class not set correctly")
                   return
               }

               vc.post = post

               guard let nav = self.navigationController else {
                   assertionFailure("FeedViewController is not inside a UINavigationController")
                   return
               }

               nav.pushViewController(vc, animated: true)
           }

           return cell
       }
    
    
}

extension FeedViewController: UITableViewDelegate { }
