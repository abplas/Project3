//
//  CommentsViewController.swift
//  Project 2-3
//
//  Created by Abel Plascencia on 3/1/26.
//

import UIKit

import ParseSwift

final class CommentsViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var commentField: UITextField!
    var post: Post!
    var comments: [Comment] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    private func fetchComments() {
        guard let postId = post.objectId else {
            print("CommentsVC: post.objectId is nil")
            return
        }

        let postPointer = Pointer<Post>(objectId: postId)

        Comment.query("post" == postPointer)
            .order([.ascending("createdAt")])
            .find { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let objects):
                    self.comments = objects
                    self.tableView.reloadData()
                case .failure(let error):
                    print("Fetch comments error:", error)
                }
            }
    }
    
    @IBAction func didTapSend(_ sender: UIButton) {
        let text = (commentField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            guard let postId = post.objectId else { return }
            guard let currentUser = User.current else { return }

            sender.isEnabled = false

            var comment = Comment()
            comment.text = text
            comment.post = Pointer<Post>(objectId: postId)
            comment.user = currentUser

            comment.save { [weak self] result in
                guard let self else { return }
                sender.isEnabled = true

                switch result {
                case .success(let saved):
                    self.commentField.text = ""
                    self.comments.append(saved)

                    let newIndexPath = IndexPath(row: self.comments.count - 1, section: 0)
                    self.tableView.insertRows(at: [newIndexPath], with: .automatic)
                    self.tableView.scrollToRow(at: newIndexPath, at: .bottom, animated: true)

                case .failure(let error):
                    print("Save comment error:", error)
                }
            }
        }
}

extension CommentsViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        return comments.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "CommentCell")
        
        let comment = comments[indexPath.row]
        cell.textLabel?.text = comment.text
        cell.detailTextLabel?.text = comment.user?.username
        
        return cell
    }
}
